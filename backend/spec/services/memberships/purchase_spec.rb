require "rails_helper"

RSpec.describe Memberships::Purchase do
  let(:user) { create(:user) }
  let(:plan) { create(:premium_plan) }

  it "creates a fresh active membership and matching payment" do
    result = described_class.call(user: user, plan: plan, card_token: "tok_visa")

    expect(result.membership).to be_persisted
    expect(result.membership.state).to eq("active")
    expect(result.membership.source).to eq("purchase")
    expect(result.payment.status).to eq("succeeded")
    expect(result.payment.membership).to eq(result.membership)
  end

  it "rolls back the entire transaction when the PG declines" do
    expect {
      described_class.call(user: user, plan: plan, card_token: "tok_visa_declined")
    }.to raise_error(PaymentGateway::DeclinedError)
      .and change(Membership, :count).by(0)
      .and change(Payment, :count).by(0)
  end

  describe "stacking on existing active membership of the same plan" do
    it "extends expires_at instead of creating a parallel row" do
      first = described_class.call(user: user, plan: plan, card_token: "tok_visa")
      first_expires = first.membership.expires_at

      second = described_class.call(user: user, plan: plan, card_token: "tok_visa")

      expect(user.memberships.where(membership_plan_id: plan.id).count).to eq(1)
      expect(second.membership.id).to eq(first.membership.id)
      # Premium plan = 60 days; second buy stacks another 60.
      expect(second.membership.expires_at).to be_within(2.seconds).of(first_expires + 60.days)
    end

    it "still records both payments and ties them to the (single) membership" do
      first  = described_class.call(user: user, plan: plan, card_token: "tok_visa")
      second = described_class.call(user: user, plan: plan, card_token: "tok_mastercard")

      expect(Payment.where(membership_id: first.membership.id).count).to eq(2)
      expect(second.payment.membership_id).to eq(first.membership.id)
    end

    it "creates a separate row for a different plan class" do
      basic = create(:basic_plan)
      described_class.call(user: user, plan: basic, card_token: "tok_visa")
      described_class.call(user: user, plan: plan,  card_token: "tok_visa")

      expect(user.memberships.count).to eq(2)
      expect(user.memberships.pluck(:membership_plan_id)).to contain_exactly(basic.id, plan.id)
    end

    it "creates a NEW row when the only same-plan membership has expired" do
      create(:membership, :expired, user: user, membership_plan: plan)
      result = described_class.call(user: user, plan: plan, card_token: "tok_visa")

      expect(user.memberships.where(membership_plan_id: plan.id).count).to eq(2)
      expect(result.membership.state).to eq("active")
    end

    it "creates a NEW row when the only same-plan membership has been revoked" do
      create(:membership, user: user, membership_plan: plan, status: "revoked")
      result = described_class.call(user: user, plan: plan, card_token: "tok_visa")

      expect(user.memberships.where(membership_plan_id: plan.id).count).to eq(2)
      expect(result.membership.state).to eq("active")
    end
  end
end

require "rails_helper"

RSpec.describe Memberships::AdminGrant do
  let(:user) { create(:user) }

  it "honours the plan's natural day duration" do
    plan = create(:premium_plan)
    Timecop.freeze(Time.utc(2026, 4, 9, 10, 0, 0)) if defined?(Timecop)
    membership = described_class.call(user: user, plan: plan)
    expect(membership.expires_at).to be_within(2.seconds).of(membership.started_at + 60.days)
  end

  it "honours an explicit duration_seconds override (30s expiry demo path)" do
    plan = create(:premium_plan)
    membership = described_class.call(user: user, plan: plan, duration_seconds: 30)
    expect(membership.expires_at).to be_within(2.seconds).of(membership.started_at + 30.seconds)
  end

  it "lets the admin override with explicit duration_days" do
    plan = create(:premium_plan)
    membership = described_class.call(user: user, plan: plan, duration_days: 7)
    expect(membership.expires_at).to be_within(2.seconds).of(membership.started_at + 7.days)
  end

  it "duration_seconds takes precedence over duration_days when both supplied" do
    plan = create(:premium_plan)
    membership = described_class.call(user: user, plan: plan, duration_days: 7, duration_seconds: 10)
    expect(membership.expires_at).to be_within(2.seconds).of(membership.started_at + 10.seconds)
  end

  it "is the only way to create an admin_grant membership" do
    plan = create(:basic_plan)
    membership = described_class.call(user: user, plan: plan)
    expect(membership.source).to eq("admin_grant")
  end

  describe "stacking on existing active membership of the same plan" do
    let(:plan) { create(:premium_plan) }

    it "extends expires_at instead of creating a parallel row when same plan is active" do
      first  = described_class.call(user: user, plan: plan, duration_days: 7)
      first_expires = first.expires_at

      second = described_class.call(user: user, plan: plan, duration_days: 14)

      expect(user.memberships.where(membership_plan_id: plan.id).count).to eq(1)
      expect(second.id).to eq(first.id)
      expect(second.expires_at).to be_within(2.seconds).of(first_expires + 14.days)
    end

    it "stacks seconds-based grants too (30s expiry demo path)" do
      first  = described_class.call(user: user, plan: plan, duration_seconds: 30)
      first_expires = first.expires_at

      second = described_class.call(user: user, plan: plan, duration_seconds: 30)

      expect(second.id).to eq(first.id)
      expect(second.expires_at).to be_within(2.seconds).of(first_expires + 30.seconds)
    end

    it "creates a NEW row when the existing active membership is for a different plan" do
      basic   = create(:basic_plan)
      described_class.call(user: user, plan: basic, duration_days: 7)
      described_class.call(user: user, plan: plan,  duration_days: 14)

      expect(user.memberships.count).to eq(2)
    end

    it "creates a NEW row when the existing same-plan membership has already expired" do
      old = create(:membership, :expired, user: user, membership_plan: plan)
      new = described_class.call(user: user, plan: plan, duration_days: 14)

      expect(new.id).not_to eq(old.id)
      expect(user.memberships.where(membership_plan_id: plan.id).count).to eq(2)
    end
  end

  describe "duration validation" do
    let(:plan) { create(:premium_plan) }

    it "rejects zero duration_days" do
      expect { described_class.call(user: user, plan: plan, duration_days: 0) }
        .to raise_error(Memberships::AdminGrant::InvalidDuration)
    end

    it "rejects negative duration_days" do
      expect { described_class.call(user: user, plan: plan, duration_days: -3) }
        .to raise_error(Memberships::AdminGrant::InvalidDuration)
    end

    it "rejects duration_days beyond MAX_GRANT_DAYS" do
      expect {
        described_class.call(user: user, plan: plan, duration_days: Memberships::AdminGrant::MAX_GRANT_DAYS + 1)
      }.to raise_error(Memberships::AdminGrant::InvalidDuration, /cannot exceed/)
    end

    it "accepts the boundary day value (MAX_GRANT_DAYS)" do
      membership = described_class.call(user: user, plan: plan, duration_days: Memberships::AdminGrant::MAX_GRANT_DAYS)
      expect(membership.expires_at).to be > membership.started_at
    end

    it "rejects zero / negative / over-cap duration_seconds" do
      expect { described_class.call(user: user, plan: plan, duration_seconds: 0) }
        .to raise_error(Memberships::AdminGrant::InvalidDuration)
      expect { described_class.call(user: user, plan: plan, duration_seconds: -1) }
        .to raise_error(Memberships::AdminGrant::InvalidDuration)
      expect {
        described_class.call(user: user, plan: plan, duration_seconds: Memberships::AdminGrant::MAX_GRANT_SECONDS + 1)
      }.to raise_error(Memberships::AdminGrant::InvalidDuration)
    end
  end
end

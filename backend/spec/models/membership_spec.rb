require 'rails_helper'

RSpec.describe Membership, type: :model do
  subject { build(:membership) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:membership_plan) }
  it { is_expected.to validate_inclusion_of(:status).in_array(Membership::STATUSES) }
  it { is_expected.to validate_inclusion_of(:source).in_array(Membership::SOURCES) }

  it "rejects expires_at before started_at" do
    m = build(:membership, started_at: Time.current, expires_at: 1.minute.ago)
    expect(m).not_to be_valid
    expect(m.errors[:expires_at]).to be_present
  end

  describe "#state" do
    it "is active when status is active and not expired" do
      expect(create(:membership).state).to eq("active")
    end

    it "is expired when expires_at is in the past" do
      expect(create(:membership, :expired).state).to eq("expired")
    end

    it "is revoked when status column is revoked" do
      expect(create(:membership, :revoked).state).to eq("revoked")
    end

    it "treats revoked status as revoked even before expiry" do
      m = create(:membership, :revoked, expires_at: 30.days.from_now)
      expect(m.state).to eq("revoked")
    end
  end

  describe ".active_now" do
    it "excludes expired and revoked memberships" do
      ok       = create(:membership)
      _exp     = create(:membership, :expired)
      _revoked = create(:membership, :revoked)

      expect(Membership.active_now).to eq([ok])
    end
  end

  describe "#revoke!" do
    it "sets status to revoked" do
      m = create(:membership)
      m.revoke!
      expect(m.reload.status).to eq("revoked")
      expect(m).not_to be_active
    end
  end
end

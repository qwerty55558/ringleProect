require 'rails_helper'

RSpec.describe User, type: :model do
  describe "validations" do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_inclusion_of(:role).in_array(User::ROLES) }
  end

  describe "#admin?" do
    it "is true for admin role" do
      expect(build(:admin).admin?).to be true
    end

    it "is false for regular user" do
      expect(build(:user).admin?).to be false
    end
  end

  describe "feature lookups" do
    let(:user) { create(:user) }

    it "returns the union of features across active memberships" do
      basic   = create(:basic_plan)
      premium = create(:premium_plan)
      create(:membership, user: user, membership_plan: basic)
      create(:membership, user: user, membership_plan: premium)

      expect(user.available_features).to match_array(%w[study talk analysis])
      expect(user.has_feature?(:talk)).to be true
      expect(user.has_feature?(:nonsense)).to be false
    end

    it "ignores expired memberships" do
      premium = create(:premium_plan)
      create(:membership, :expired, user: user, membership_plan: premium)

      expect(user.available_features).to be_empty
    end

    it "ignores revoked memberships" do
      premium = create(:premium_plan)
      create(:membership, :revoked, user: user, membership_plan: premium)

      expect(user.available_features).to be_empty
    end
  end
end

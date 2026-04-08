require 'rails_helper'

RSpec.describe MembershipPlan, type: :model do
  subject { build(:basic_plan) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_uniqueness_of(:name) }
  it { is_expected.to validate_numericality_of(:duration_days).is_greater_than(0) }
  it { is_expected.to validate_numericality_of(:price_cents).is_greater_than_or_equal_to(0) }

  it "rejects unknown features" do
    plan = build(:membership_plan, features: %w[study mystery])
    expect(plan).not_to be_valid
    expect(plan.errors[:features]).to be_present
  end

  it "accepts a subset of known features" do
    expect(build(:membership_plan, features: %w[study talk])).to be_valid
  end

  describe ".active" do
    it "returns only active plans" do
      a = create(:membership_plan, active: true)
      create(:membership_plan, active: false)
      expect(MembershipPlan.active).to eq([a])
    end
  end
end

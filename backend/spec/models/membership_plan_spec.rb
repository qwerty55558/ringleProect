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

  describe "#expiry_from" do
    let(:start) { Time.utc(2026, 4, 9, 10, 0, 0) }

    it "uses duration_days when duration_seconds is nil" do
      plan = build(:membership_plan, duration_days: 30, duration_seconds: nil)
      expect(plan.expiry_from(start)).to eq(start + 30.days)
    end

    it "prefers duration_seconds when both are present" do
      plan = build(:short_expiry_plan)
      expect(plan.expiry_from(start)).to eq(start + 30.seconds)
    end
  end

  describe "#duration_label" do
    it "returns days for day-based plans" do
      expect(build(:membership_plan, duration_days: 30).duration_label).to eq("30일")
    end

    it "returns seconds when duration_seconds is set" do
      expect(build(:short_expiry_plan).duration_label).to eq("30초")
    end
  end

  describe "duration_seconds validation" do
    it "rejects non-positive values" do
      expect(build(:membership_plan, duration_seconds: 0)).not_to be_valid
    end

    it "allows nil" do
      expect(build(:membership_plan, duration_seconds: nil)).to be_valid
    end
  end
end

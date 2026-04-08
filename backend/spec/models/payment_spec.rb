require 'rails_helper'

RSpec.describe Payment, type: :model do
  subject { build(:payment) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:membership_plan) }
  it { is_expected.to belong_to(:membership).optional }
  it { is_expected.to validate_inclusion_of(:status).in_array(Payment::STATUSES) }
  it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than_or_equal_to(0) }
end

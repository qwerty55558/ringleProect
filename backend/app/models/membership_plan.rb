class MembershipPlan < ApplicationRecord
  FEATURES = %w[study talk analysis].freeze

  has_many :memberships, dependent: :restrict_with_error
  has_many :payments, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :duration_days, numericality: { greater_than: 0 }
  validate :features_must_be_known

  scope :active, -> { where(active: true) }

  def features
    super || []
  end

  private

  def features_must_be_known
    return if features.is_a?(Array) && (features - FEATURES).empty?

    errors.add(:features, "must be a subset of #{FEATURES.join(', ')}")
  end
end

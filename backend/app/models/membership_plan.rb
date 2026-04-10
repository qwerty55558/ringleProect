class MembershipPlan < ApplicationRecord
  FEATURES = %w[study talk analysis].freeze

  has_many :memberships, dependent: :restrict_with_error
  has_many :payments, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :duration_days, numericality: { greater_than: 0 }
  validates :duration_seconds, numericality: { greater_than: 0 }, allow_nil: true
  validate :features_must_be_known

  scope :active, -> { where(active: true) }

  def features
    super || []
  end

  # Returns the absolute time at which a freshly issued membership for
  # this plan should expire. Sub-day granularity (`duration_seconds`)
  # takes precedence so the 30-second demo plan can simulate expiry
  # without polluting the day-based plans.
  def expiry_from(start_at)
    extend_from(start_at)
  end

  # Adds this plan's natural duration to a base time. Used by both the
  # "freshly issued" path (base = now) and the "stack on top of an
  # existing active membership" path (base = existing expires_at) so
  # the formula stays in one place.
  def extend_from(base_at)
    return base_at + duration_seconds.seconds if duration_seconds.present?

    base_at + duration_days.days
  end

  # Adds an explicit override duration (in seconds) to a base time.
  # AdminGrant uses this when the operator types a custom value into
  # the duration field — same stacking semantics as `extend_from`.
  def self.extend_by(base_at, seconds:)
    base_at + seconds
  end

  # Human-friendly duration label for the API. Days are still days; the
  # 30-second plan returns "30초" so the frontend doesn't have to know
  # the formula.
  def duration_label
    return "#{duration_seconds}초" if duration_seconds.present?

    "#{duration_days}일"
  end

  private

  def features_must_be_known
    return if features.is_a?(Array) && (features - FEATURES).empty?

    errors.add(:features, "must be a subset of #{FEATURES.join(', ')}")
  end
end

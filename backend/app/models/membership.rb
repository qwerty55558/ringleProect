class Membership < ApplicationRecord
  STATUSES = %w[active revoked].freeze
  SOURCES  = %w[purchase admin_grant].freeze

  belongs_to :user
  belongs_to :membership_plan
  has_one :payment, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :started_at, :expires_at, presence: true
  validate :expires_after_started

  scope :active_now, -> { where(status: "active").where("expires_at > ?", Time.current) }
  scope :expired,    -> { where("expires_at <= ?", Time.current) }

  # Lazy state computation. status column tracks revocation; expiry is time-based.
  def state
    return "revoked" if status == "revoked"
    return "expired" if expires_at <= Time.current

    "active"
  end

  def active?
    state == "active"
  end

  def revoke!
    update!(status: "revoked")
  end

  private

  def expires_after_started
    return if started_at.blank? || expires_at.blank?

    errors.add(:expires_at, "must be after started_at") if expires_at <= started_at
  end
end

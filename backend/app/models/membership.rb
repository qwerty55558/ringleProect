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

  # Wake up SSE subscribers the moment a membership row changes.
  # Two parallel buses, fanned out by a single after_commit hook:
  #
  #   Me::Bus              — per-user channel, drives /me/stream so the
  #                          owning learner sees their own state update
  #                          on every page (home, conversation, study…).
  #   Admin::MembershipBus — global broadcast, drives the admin tab's
  #                          /admin/memberships/stream so any admin
  #                          watching the dashboard sees grants /
  #                          revokes / new purchases for ANY user in
  #                          real time.
  #
  # Both are in-process Thread::Queue fan-outs — no DB I/O, no Redis.
  # Time-based expiry doesn't go through this hook (no row mutation
  # happens); each SSE controller handles that side via a Queue#pop
  # timeout deadline.
  after_commit :notify_subscribers

  def notify_subscribers
    Me::Bus.publish(user_id)
    Admin::MembershipBus.publish
  end

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

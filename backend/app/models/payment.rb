class Payment < ApplicationRecord
  STATUSES = %w[succeeded failed].freeze

  belongs_to :user
  belongs_to :membership_plan
  belongs_to :membership, optional: true

  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :pg_transaction_id, uniqueness: true, allow_nil: true
end

class Analysis < ApplicationRecord
  belongs_to :conversation

  STATUSES = %w[pending completed failed].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :analyzed_at, presence: true

  def self.latest_for(conversation)
    where(conversation: conversation).order(created_at: :desc).first
  end

  def pending?  = status == "pending"
  def completed? = status == "completed"
  def failed?   = status == "failed"
end

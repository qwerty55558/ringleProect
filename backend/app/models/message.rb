class Message < ApplicationRecord
  ROLES = %w[user assistant].freeze

  belongs_to :conversation
  has_one_attached :audio

  validates :role, inclusion: { in: ROLES }
  validates :text, presence: true

  delegate :user, to: :conversation

  def audio?
    audio.attached?
  end
end

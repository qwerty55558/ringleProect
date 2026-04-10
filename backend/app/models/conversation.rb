class Conversation < ApplicationRecord
  belongs_to :user
  belongs_to :study_material, optional: true
  has_many :messages, -> { order(:position) }, dependent: :destroy
  has_many :analyses, dependent: :destroy

  def append_message!(role:, text:, audio: nil, content_hash: nil)
    transaction do
      next_position = (messages.maximum(:position) || -1) + 1
      message = messages.create!(
        role: role,
        text: text,
        position: next_position,
        content_hash: content_hash
      )
      message.audio.attach(audio) if audio.present?
      message
    end
  end
end

class TtsArtifact < ApplicationRecord
  has_one_attached :audio

  validates :content_hash, :voice_id, :model_id, presence: true
  validates :content_hash, uniqueness: { scope: %i[voice_id model_id] }

  # SHA256 of the text — collision-resistant lookup key. We could include
  # voice/model in the hash itself, but keeping them as columns makes the
  # cache trivially inspectable in psql / Rails console.
  def self.hash_for(text)
    Digest::SHA256.hexdigest(text.to_s.strip)
  end
end

class SttArtifact < ApplicationRecord
  has_one_attached :audio

  validates :audio_hash, :text, :mime_type, presence: true
  validates :audio_hash, uniqueness: true
  validates :slug, uniqueness: true, allow_nil: true

  scope :fixtures, -> { where.not(slug: nil).order(:slug) }

  def self.hash_for(bytes)
    Digest::SHA256.hexdigest(bytes.to_s)
  end

  def fixture?
    slug.present?
  end
end

class User < ApplicationRecord
  ROLES = %w[user admin].freeze

  has_many :memberships, dependent: :destroy
  has_many :payments, dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }

  def admin?
    role == "admin"
  end

  # All currently active (non-expired, non-revoked) memberships
  def active_memberships
    memberships.active_now
  end

  # Union of features granted by any active membership
  def available_features
    active_memberships.includes(:membership_plan).flat_map { |m| m.membership_plan.features }.uniq
  end

  def has_feature?(feature)
    available_features.include?(feature.to_s)
  end
end

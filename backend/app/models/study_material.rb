class StudyMaterial < ApplicationRecord
  # Four-tier difficulty: 입문 / 초급 / 중급 / 고급. The frontend
  # `LEVEL_LABEL` map maps each constant to its Korean display name.
  LEVELS     = %w[novice beginner intermediate advanced].freeze
  # `conversation` (회화) was added so the curriculum can include free-
  # form conversational scenarios alongside the situation-driven
  # daily/business/travel/hobby/academic categories.
  CATEGORIES = %w[daily business travel hobby academic conversation].freeze

  validates :slug,             presence: true, uniqueness: true
  validates :title,            presence: true
  validates :description,      presence: true
  validates :scenario_prompt,  presence: true
  validates :level,            inclusion: { in: LEVELS }
  validates :category,         inclusion: { in: CATEGORIES }

  scope :for_level,    ->(level)    { where(level: level) }
  scope :for_category, ->(category) { where(category: category) }

  def key_expressions
    super || []
  end

  def example_dialogue
    super || []
  end
end

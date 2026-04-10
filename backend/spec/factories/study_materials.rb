FactoryBot.define do
  factory :study_material do
    sequence(:slug) { |n| "study-#{n}" }
    sequence(:title) { |n| "Topic #{n}" }
    level { "beginner" }
    category { "daily" }
    description { "테스트용 시나리오" }
    scenario_prompt { "Stay on topic." }
    key_expressions { ["expr 1", "expr 2"] }
    example_dialogue { [{ "role" => "assistant", "text" => "hi" }] }
    ai_generated { false }
  end
end

FactoryBot.define do
  factory :conversation do
    user
    title { nil }
  end

  factory :message do
    conversation
    role { "user" }
    sequence(:text) { |n| "test message #{n}" }
    position { 0 }
  end
end

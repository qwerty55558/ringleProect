FactoryBot.define do
  factory :membership do
    user
    association :membership_plan, factory: :basic_plan
    started_at { Time.current }
    expires_at { 30.days.from_now }
    status { "active" }
    source { "purchase" }

    trait :expired do
      started_at { 60.days.ago }
      expires_at { 1.day.ago }
    end

    trait :revoked do
      status { "revoked" }
    end

    trait :admin_grant do
      source { "admin_grant" }
    end
  end
end

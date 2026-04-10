FactoryBot.define do
  factory :membership_plan do
    sequence(:name) { |n| "Plan #{n}" }
    price_cents { 10_000 }
    duration_days { 30 }
    features { %w[study] }
    active { true }

    factory :basic_plan do
      sequence(:name) { |n| "Basic #{n}" }
      features { %w[study] }
    end

    factory :premium_plan do
      sequence(:name) { |n| "Premium #{n}" }
      features { %w[study talk analysis] }
      duration_days { 60 }
    end

    # Sub-day expiry — used to drive the membership-expired flow in
    # tests without waiting in real time.
    factory :short_expiry_plan do
      sequence(:name) { |n| "Short #{n}" }
      features { %w[study talk analysis] }
      duration_days { 1 }
      duration_seconds { 30 }
    end
  end
end

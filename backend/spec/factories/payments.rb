FactoryBot.define do
  factory :payment do
    user
    association :membership_plan, factory: :basic_plan
    membership { nil }
    amount_cents { 10_000 }
    status { "succeeded" }
    sequence(:pg_transaction_id) { |n| "mock_pg_tx_#{n}" }
  end
end

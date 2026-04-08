module Memberships
  # Encapsulates the user-driven purchase flow:
  #   1. charge the (mock) PG
  #   2. create the Membership row with source=purchase
  #   3. record a Payment row tied to both
  #
  # Wrapped in a single DB transaction so a failed step rolls everything back.
  class Purchase
    Result = Struct.new(:membership, :payment, keyword_init: true)

    def self.call(user:, plan:, idempotency_key: nil)
      raise ArgumentError, "plan inactive" unless plan.active?

      ActiveRecord::Base.transaction do
        charge = PaymentGateway.charge!(
          user: user,
          amount_cents: plan.price_cents,
          idempotency_key: idempotency_key
        )

        now = Time.current
        membership = user.memberships.create!(
          membership_plan: plan,
          started_at: now,
          expires_at: now + plan.duration_days.days,
          status: "active",
          source: "purchase"
        )

        payment = Payment.create!(
          user: user,
          membership_plan: plan,
          membership: membership,
          amount_cents: charge.amount_cents,
          status: "succeeded",
          pg_transaction_id: charge.transaction_id
        )

        Result.new(membership: membership, payment: payment)
      end
    end
  end
end

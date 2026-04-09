module Memberships
  # Encapsulates the user-driven purchase flow:
  #   1. charge the (mock) PG with the supplied card token
  #   2. EITHER extend an existing active membership of the SAME plan
  #      (stacking duration on top of its expires_at) OR create a new
  #      Membership row with source=purchase
  #   3. record a Payment row tied to whichever membership we landed on
  #
  # Stacking semantics: if Danny already has 14 days left on his
  # Premium plan and buys another month, his expires_at moves out by
  # the plan's natural duration — he doesn't end up with two parallel
  # Premium rows. Different plans (Basic vs Premium) stay separate, so
  # buying Basic while you have Premium doesn't merge them.
  #
  # Wrapped in a single DB transaction so a failed step rolls everything back.
  class Purchase
    Result = Struct.new(:membership, :payment, :charge, keyword_init: true)

    def self.call(user:, plan:, card_token: nil, idempotency_key: nil)
      raise ArgumentError, "plan inactive" unless plan.active?

      ActiveRecord::Base.transaction do
        charge = PaymentGateway.charge!(
          user: user,
          amount_cents: plan.price_cents,
          card_token: card_token,
          idempotency_key: idempotency_key
        )

        now = Time.current
        existing = user.memberships
                       .where(membership_plan_id: plan.id, status: "active")
                       .where("expires_at > ?", now)
                       .order(expires_at: :desc)
                       .first

        membership =
          if existing
            existing.update!(expires_at: plan.extend_from(existing.expires_at))
            existing
          else
            user.memberships.create!(
              membership_plan: plan,
              started_at: now,
              expires_at: plan.expiry_from(now),
              status: "active",
              source: "purchase"
            )
          end

        payment = Payment.create!(
          user: user,
          membership_plan: plan,
          membership: membership,
          amount_cents: charge.amount_cents,
          status: "succeeded",
          pg_transaction_id: charge.transaction_id
        )

        Result.new(membership: membership, payment: payment, charge: charge)
      end
    end
  end
end

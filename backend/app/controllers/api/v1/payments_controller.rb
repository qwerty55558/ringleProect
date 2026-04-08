module Api
  module V1
    class PaymentsController < ApplicationController
      before_action :require_user!

      def create
        plan = MembershipPlan.active.find(params.require(:membership_plan_id))
        result = Memberships::Purchase.call(
          user: current_user,
          plan: plan,
          idempotency_key: params[:idempotency_key]
        )

        render status: :created, json: {
          payment: {
            id: result.payment.id,
            amount_cents: result.payment.amount_cents,
            status: result.payment.status,
            pg_transaction_id: result.payment.pg_transaction_id
          },
          membership: {
            id: result.membership.id,
            plan_id: result.membership.membership_plan_id,
            started_at: result.membership.started_at.iso8601,
            expires_at: result.membership.expires_at.iso8601,
            state: result.membership.state
          }
        }
      rescue PaymentGateway::Error => e
        render status: :payment_required, json: { error: "payment_failed", message: e.message }
      end
    end
  end
end

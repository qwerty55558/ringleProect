module Api
  module V1
    class PaymentsController < ApplicationController
      before_action :require_user!

      # GET /api/v1/payments/test_cards
      # Lets the frontend render a "pick a test card" picker that maps
      # 1:1 onto the PaymentGateway::TEST_CARDS registry.
      def test_cards
        render json: PaymentGateway.test_cards
      end

      # POST /api/v1/payments
      # Body:
      #   { membership_plan_id: 1, payment_method: { card_token: "tok_visa" } }
      def create
        plan = MembershipPlan.active.find(params.require(:membership_plan_id))
        result = Memberships::Purchase.call(
          user: current_user,
          plan: plan,
          card_token: card_token_param,
          idempotency_key: params[:idempotency_key]
        )

        render status: :created, json: {
          payment: {
            id: result.payment.id,
            amount_cents: result.payment.amount_cents,
            status: result.payment.status,
            pg_transaction_id: result.payment.pg_transaction_id,
            card_brand: result.charge.card_brand
          },
          membership: {
            id: result.membership.id,
            plan_id: result.membership.membership_plan_id,
            started_at: result.membership.started_at.iso8601,
            expires_at: result.membership.expires_at.iso8601,
            state: result.membership.state
          }
        }
      rescue PaymentGateway::DeclinedError => e
        render status: :payment_required,
               json: { error: "payment_declined", reason: e.message }
      rescue PaymentGateway::ProcessingError => e
        render status: :bad_gateway,
               json: { error: "payment_processing_error", reason: e.message }
      end

      private

      def card_token_param
        method = params[:payment_method]
        method.is_a?(ActionController::Parameters) ? method[:card_token] : nil
      end
    end
  end
end

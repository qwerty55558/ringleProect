module Api
  module V1
    class MembershipPlansController < ApplicationController
      def index
        plans = MembershipPlan.active.order(:price_cents)
        render json: plans.map { |p|
          {
            id: p.id,
            name: p.name,
            price_cents: p.price_cents,
            duration_days: p.duration_days,
            duration_seconds: p.duration_seconds,
            duration_label: p.duration_label,
            features: p.features
          }
        }
      end
    end
  end
end

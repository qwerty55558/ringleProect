module Api
  module V1
    class MeController < ApplicationController
      before_action :require_user!

      def show
        render json: {
          user: serialize_user(current_user),
          memberships: current_user.memberships.includes(:membership_plan).map { |m| serialize_membership(m) },
          features: current_user.available_features
        }
      end

      private

      def serialize_user(user)
        { id: user.id, email: user.email, name: user.name, role: user.role }
      end

      def serialize_membership(m)
        {
          id: m.id,
          plan: { id: m.membership_plan.id, name: m.membership_plan.name, features: m.membership_plan.features },
          state: m.state,
          source: m.source,
          started_at: m.started_at.iso8601,
          expires_at: m.expires_at.iso8601
        }
      end
    end
  end
end

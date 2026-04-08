module Api
  module V1
    class MembershipsController < ApplicationController
      before_action :require_user!

      def index
        memberships = current_user.memberships.includes(:membership_plan).order(created_at: :desc)
        render json: memberships.map { |m|
          {
            id: m.id,
            plan: { id: m.membership_plan.id, name: m.membership_plan.name, features: m.membership_plan.features },
            state: m.state,
            source: m.source,
            started_at: m.started_at.iso8601,
            expires_at: m.expires_at.iso8601
          }
        }
      end
    end
  end
end

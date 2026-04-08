module Api
  module V1
    module Admin
      class UsersController < ApplicationController
        before_action :require_admin!

        def index
          users = User.includes(memberships: :membership_plan).order(:id)
          render json: users.map { |u|
            {
              id: u.id,
              email: u.email,
              name: u.name,
              role: u.role,
              memberships: u.memberships.map { |m|
                {
                  id: m.id,
                  plan: { id: m.membership_plan.id, name: m.membership_plan.name, features: m.membership_plan.features },
                  state: m.state,
                  source: m.source,
                  started_at: m.started_at.iso8601,
                  expires_at: m.expires_at.iso8601
                }
              }
            }
          }
        end
      end
    end
  end
end

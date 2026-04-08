module Api
  module V1
    module Admin
      class MembershipsController < ApplicationController
        before_action :require_admin!

        def create
          user = User.find(params.require(:user_id))
          plan = MembershipPlan.active.find(params.require(:membership_plan_id))
          membership = Memberships::AdminGrant.call(
            user: user,
            plan: plan,
            duration_days: params[:duration_days]
          )

          render status: :created, json: {
            id: membership.id,
            user_id: user.id,
            plan: { id: plan.id, name: plan.name, features: plan.features },
            state: membership.state,
            source: membership.source,
            started_at: membership.started_at.iso8601,
            expires_at: membership.expires_at.iso8601
          }
        end

        def destroy
          membership = Membership.find(params[:id])
          membership.revoke!
          head :no_content
        end

        # Hard-deletes every membership in the database. Used by the dev
        # tools panel to wipe state between demo runs. Admin-only by way
        # of the before_action.
        #
        # We use `destroy_all` (not `delete_all`) so the
        # `Membership has_one :payment, dependent: :nullify` callback
        # fires — otherwise the foreign key on payments.membership_id
        # blows up the transaction.
        def destroy_all
          count = Membership.count
          Membership.destroy_all
          render json: { deleted: count }
        end
      end
    end
  end
end

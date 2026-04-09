module Api
  module V1
    class MeController < ApplicationController
      before_action :require_user!

      def show
        render json: Me::Snapshot.call(current_user)
      end
    end
  end
end

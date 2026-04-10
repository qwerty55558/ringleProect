module Api
  module V1
    module Admin
      class AnalysesController < ApplicationController
        before_action :require_admin!

        def destroy_all
          count = Analysis.count
          Analysis.destroy_all
          render json: { deleted: count }
        end
      end
    end
  end
end

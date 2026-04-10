module Api
  module V1
    module Admin
      class ConversationsController < ApplicationController
        before_action :require_admin!

        def destroy_all
          count = Conversation.count
          Conversation.destroy_all
          render json: { deleted: count }
        end
      end
    end
  end
end

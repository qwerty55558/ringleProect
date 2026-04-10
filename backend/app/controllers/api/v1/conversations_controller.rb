module Api
  module V1
    class ConversationsController < ApplicationController
      before_action :require_user!
      before_action :require_talk_feature!, only: [:create]

      # GET /api/v1/conversations
      def index
        conversations = current_user.conversations.order(created_at: :desc)
        render json: conversations.map { |c| serialize(c) }
      end

      # POST /api/v1/conversations
      def create
        conversation = current_user.conversations.create!(title: params[:title])
        render status: :created, json: serialize(conversation, with_messages: true)
      end

      # GET /api/v1/conversations/:id
      def show
        conversation = current_user.conversations.find(params[:id])
        render json: serialize(conversation, with_messages: true)
      end

      # DELETE /api/v1/conversations/:id
      # Removes the conversation, all its messages, AND every attached
      # audio blob (Active Storage cascades via dependent: :destroy on
      # has_one_attached). After this call the user's replays are gone.
      def destroy
        conversation = current_user.conversations.find(params[:id])
        conversation.destroy!
        head :no_content
      end

      private

      def has_many_user_relation
        current_user.conversations
      end

      def serialize(conversation, with_messages: false)
        payload = {
          id: conversation.id,
          title: conversation.title,
          created_at: conversation.created_at.iso8601
        }
        if with_messages
          payload[:messages] = conversation.messages.map { |m| MessageSerializer.call(m) }
        end
        payload
      end

      def require_talk_feature!
        return if current_user.has_feature?("talk")

        render status: :forbidden, json: { error: "membership_required", feature: "talk" }
      end
    end
  end
end

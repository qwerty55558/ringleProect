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
        conversation = current_user.conversations.create!(
          title: params[:title],
          study_material_id: params[:study_material_id]
        )
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

      # DELETE /api/v1/conversations
      def destroy_all
        count = current_user.conversations.count
        current_user.conversations.destroy_all
        render json: { deleted: count }
      end

      private

      def has_many_user_relation
        current_user.conversations
      end

      def serialize(conversation, with_messages: false)
        payload = {
          id: conversation.id,
          title: conversation.title,
          created_at: conversation.created_at.iso8601,
          message_count: conversation.messages.size,
          study_material_id: conversation.study_material_id
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

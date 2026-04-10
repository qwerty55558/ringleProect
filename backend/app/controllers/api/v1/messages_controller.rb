module Api
  module V1
    class MessagesController < ApplicationController
      MAX_AUDIO_BYTES = 4 * 1024 * 1024 # 4 MB — covers a 30s voiced WAV @ 16kHz

      before_action :require_user!
      before_action :require_talk_feature!
      before_action :load_conversation

      # POST /api/v1/conversations/:conversation_id/messages
      # Multipart body:
      #   role: "user" | "assistant"
      #   text: string
      #   audio: (optional) file part
      #
      # Persists the turn so it survives reload + lets the per-message
      # replay button serve from disk forever (until the user explicitly
      # deletes the conversation).
      def create
        role = params.require(:role)
        text = params.require(:text)
        audio = params[:audio]

        if audio.present?
          raise ActionController::BadRequest, "audio too large" if audio.size > MAX_AUDIO_BYTES
        end

        message = @conversation.append_message!(
          role: role,
          text: text,
          audio: audio,
          content_hash: TtsArtifact.hash_for(text)
        )

        render status: :created, json: MessageSerializer.call(message)
      end

      # GET /api/v1/conversations/:conversation_id/messages/:id/audio
      # Streams the cached blob. We deliberately use our own controller
      # (instead of the Active Storage URL helpers) so we can enforce
      # ownership: a user can only fetch audio that belongs to one of
      # their own conversations.
      def audio
        message = @conversation.messages.find(params[:id])
        unless message.audio.attached?
          return render status: :not_found, json: { error: "audio_not_attached" }
        end

        response.headers["Cache-Control"] = "private, max-age=86400"
        send_data message.audio.download,
                  type: message.audio.content_type || "application/octet-stream",
                  disposition: "inline"
      end

      private

      def load_conversation
        @conversation = current_user.conversations.find(params[:conversation_id])
      end

      def require_talk_feature!
        return if current_user.has_feature?("talk")

        render status: :forbidden, json: { error: "membership_required", feature: "talk" }
      end
    end
  end
end

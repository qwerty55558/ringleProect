module Api
  module V1
    module Ai
      class TranscriptionsController < ApplicationController
        MAX_AUDIO_BYTES = 2 * 1024 * 1024 # 2 MB after VAD trimming should be plenty

        before_action :require_user!
        before_action :require_talk_feature!

        def create
          audio = params.require(:audio)
          raise ActionController::BadRequest, "audio file too large" if audio.size > MAX_AUDIO_BYTES

          text = GeminiClient.new.transcribe(
            audio_bytes: audio.read,
            mime_type: audio.content_type.presence || "audio/webm"
          )
          render json: { text: text }
        rescue GeminiClient::Error => e
          Rails.logger.error("[ai/transcriptions] gemini error: #{e.message}")
          render status: :bad_gateway, json: { error: "stt_failed", message: e.message }
        end

        private

        def require_talk_feature!
          return if current_user.has_feature?("talk")

          render status: :forbidden, json: { error: "membership_required", feature: "talk" }
        end
      end
    end
  end
end

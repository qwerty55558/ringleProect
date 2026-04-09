module Api
  module V1
    module Ai
      class TranscriptionsController < ApplicationController
        MAX_AUDIO_BYTES = 2 * 1024 * 1024 # 2 MB after VAD trimming should be plenty

        before_action :require_user!
        before_action :require_talk_feature!

        # POST /api/v1/ai/transcriptions
        #
        # Multipart body with an `audio` file part. We hand the actual STT
        # call off to `Stt::Transcribe`, which dedup-caches identical
        # uploads in the stt_artifacts table — that's how the frontend's
        # demo fixtures (silence-tone WAVs with pre-seeded transcriptions)
        # avoid touching Gemini.
        def create
          audio = params.require(:audio)
          raise ActionController::BadRequest, "audio file too large" if audio.size > MAX_AUDIO_BYTES

          result = Stt::Transcribe.call(
            audio_bytes: audio.read,
            mime_type: audio.content_type.presence || "audio/webm"
          )
          response.headers["X-Stt-Cache"] = result.cache_hit ? "hit" : "miss"
          render json: { text: result.text, cache: result.cache_hit ? "hit" : "miss" }
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

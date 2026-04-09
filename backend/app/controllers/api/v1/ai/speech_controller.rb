module Api
  module V1
    module Ai
      # Text-to-speech proxy. Hands the actual ElevenLabs call off to
      # `Tts::Synthesize`, which de-dups identical requests via the
      # tts_artifacts cache so the same sentence is only billed once
      # across the whole product (e.g. the canned greeting).
      class SpeechController < ApplicationController
        MAX_TTS_CHARS = 1_500

        before_action :require_user!
        before_action :require_study_or_talk_feature!

        def create
          text = params.require(:text).to_s.strip
          raise ActionController::BadRequest, "text too long" if text.length > MAX_TTS_CHARS
          raise ActionController::BadRequest, "text blank"    if text.empty?

          result = Tts::Synthesize.call(text: text)
          response.headers["Cache-Control"] = "private, max-age=86400"
          response.headers["X-Tts-Cache"]   = result.cache_hit ? "hit" : "miss"
          send_data result.bytes, type: "audio/mpeg", disposition: "inline"
        rescue ElevenLabsClient::Error => e
          Rails.logger.error("[ai/speech] elevenlabs error: #{e.message}")
          render status: :bad_gateway, json: { error: "tts_failed", message: e.message }
        end

        private

        # Both Talk (full conversation) and Study (key-expression
        # pronunciation) members get to use TTS. Talk is the historical
        # caller; Study was added so a Basic learner can press "핵심
        # 표현 듣기" on the curriculum page without needing the talk
        # feature too. Cost is bounded by the global TTS cache + the
        # rack-attack throttle on /api/v1/ai/*.
        def require_study_or_talk_feature!
          return if current_user.has_feature?("talk") || current_user.has_feature?("study")

          render status: :forbidden, json: { error: "membership_required", feature: "study_or_talk" }
        end
      end
    end
  end
end

module Api
  module V1
    module Ai
      # Text-to-speech proxy. Uses ElevenLabs (10K chars/month free tier,
      # no credit card) so we don't expose the API key to the browser.
      # Returns MP3 bytes directly — the browser plays them via the
      # standard <audio> element.
      class SpeechController < ApplicationController
        MAX_TTS_CHARS = 1_500

        before_action :require_user!
        before_action :require_talk_feature!

        def create
          text = params.require(:text).to_s.strip
          raise ActionController::BadRequest, "text too long" if text.length > MAX_TTS_CHARS
          raise ActionController::BadRequest, "text blank"    if text.empty?

          mp3 = ElevenLabsClient.new.synthesize(text: text)
          response.headers["Cache-Control"] = "no-store"
          send_data mp3, type: "audio/mpeg", disposition: "inline"
        rescue ElevenLabsClient::Error => e
          Rails.logger.error("[ai/speech] elevenlabs error: #{e.message}")
          render status: :bad_gateway, json: { error: "tts_failed", message: e.message }
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

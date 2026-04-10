module Api
  module V1
    module Ai
      class TranslationsController < ApplicationController
        before_action :require_user!

        def create
          text = params.require(:text).to_s.strip
          raise ActionController::BadRequest, "text blank" if text.empty?

          cache_key = "translate:ko:#{Digest::SHA256.hexdigest(text)}"
          cached = Rails.cache.read(cache_key)
          if cached
            return render json: { translation: cached, cache: "hit" }
          end

          translation = GoogleTranslateClient.new.translate(text)

          Rails.cache.write(cache_key, translation, expires_in: 30.days)
          render json: { translation: translation, cache: "miss" }
        rescue GoogleTranslateClient::Error => e
          render status: :bad_gateway, json: { error: "translation_failed", message: e.message }
        end
      end
    end
  end
end

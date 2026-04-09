module Api
  module V1
    # Demo / office-mode helper. Lists the seeded STT fixtures (one row
    # per pre-cached example sentence) and serves their audio so the
    # frontend can replay them through Web Audio + submit them to the
    # transcription endpoint as if the user had spoken into a mic.
    #
    # Gated behind the talk feature so the same access rules as the
    # conversation page apply — there's no point exposing demo audio to
    # accounts that can't use the talk endpoint anyway.
    class SttFixturesController < ApplicationController
      before_action :require_user!
      before_action :require_talk_feature!

      def index
        fixtures = SttArtifact.fixtures
        render json: fixtures.map { |f| serialize(f) }
      end

      def audio
        fixture = SttArtifact.fixtures.find_by!(slug: params[:slug])
        unless fixture.audio.attached?
          return render status: :not_found, json: { error: "audio_not_attached" }
        end

        response.headers["Cache-Control"] = "private, max-age=86400"
        send_data fixture.audio.download,
                  type: fixture.mime_type,
                  disposition: "inline"
      end

      private

      def serialize(fixture)
        {
          slug: fixture.slug,
          label: fixture.label,
          text: fixture.text,
          mime_type: fixture.mime_type,
          byte_size: fixture.byte_size,
          audio_url: Rails.application.routes.url_helpers.audio_api_v1_stt_fixture_path(slug: fixture.slug)
        }
      end

      def require_talk_feature!
        return if current_user.has_feature?("talk")

        render status: :forbidden, json: { error: "membership_required", feature: "talk" }
      end
    end
  end
end

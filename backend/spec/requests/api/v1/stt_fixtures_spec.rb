require "rails_helper"

RSpec.describe "Api::V1::SttFixtures", type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "X-User-Id" => user.id.to_s } }

  before do
    create(:membership, user: user, membership_plan: create(:premium_plan))
    Stt::FixtureSeed.call
  end

  describe "GET /api/v1/stt_fixtures" do
    it "lists every seeded fixture for a talk-feature user" do
      get "/api/v1/stt_fixtures", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.length).to eq(Stt::FixtureLibrary::FIXTURES.length)
      expect(body.first.keys).to include("slug", "label", "text", "audio_url")
    end

    it "403s for a user without the talk feature" do
      no_talk = create(:user)
      create(:membership, user: no_talk, membership_plan: create(:basic_plan))
      get "/api/v1/stt_fixtures", headers: { "X-User-Id" => no_talk.id.to_s }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/stt_fixtures/:slug/audio" do
    it "streams the seeded WAV bytes" do
      slug = SttArtifact.fixtures.first.slug
      get "/api/v1/stt_fixtures/#{slug}/audio", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("audio/wav")
      expect(response.body[0, 4]).to eq("RIFF")
    end
  end
end

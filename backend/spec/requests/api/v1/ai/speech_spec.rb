require "rails_helper"

RSpec.describe "POST /api/v1/ai/speech", type: :request do
  let(:user) { create(:user) }
  before do
    create(:membership, user: user, membership_plan: create(:premium_plan))
    stub_const("ENV", ENV.to_h.merge("ELEVENLABS_API_KEY" => "test-key"))
    # Tts::Synthesize asks the client for the resolved voice id before
    # calling .synthesize, so we stub the lookup too.
    allow_any_instance_of(ElevenLabsClient).to receive(:voice_id).and_return("voice_x")
  end

  it "returns mp3 bytes from ElevenLabs" do
    fake_mp3 = "ID3\x04".b + ("\x00".b * 64)
    allow_any_instance_of(ElevenLabsClient).to receive(:synthesize).and_return(fake_mp3)

    post "/api/v1/ai/speech",
         params: { text: "Hi there." },
         headers: { "X-User-Id" => user.id.to_s }

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to start_with("audio/mpeg")
    expect(response.body).to eq(fake_mp3)
    expect(response.headers["X-Tts-Cache"]).to eq("miss")
  end

  it "serves the cached blob on the second request without re-calling ElevenLabs" do
    fake_mp3 = "ID3\x04".b + ("\x00".b * 64)
    allow_any_instance_of(ElevenLabsClient).to receive(:synthesize).and_return(fake_mp3)

    2.times do
      post "/api/v1/ai/speech",
           params: { text: "Cached me." },
           headers: { "X-User-Id" => user.id.to_s }
    end
    expect(response.headers["X-Tts-Cache"]).to eq("hit")
    expect(TtsArtifact.count).to eq(1)
  end

  it "rejects blank text" do
    post "/api/v1/ai/speech",
         params: { text: "  " },
         headers: { "X-User-Id" => user.id.to_s }
    expect(response).to have_http_status(:bad_request)
  end

  it "502s when ElevenLabs raises" do
    allow_any_instance_of(ElevenLabsClient).to receive(:synthesize)
      .and_raise(ElevenLabsClient::Error, "boom")
    post "/api/v1/ai/speech",
         params: { text: "Hi" },
         headers: { "X-User-Id" => user.id.to_s }
    expect(response).to have_http_status(:bad_gateway)
  end

  it "403s when the user has neither study nor talk feature" do
    other = create(:user)
    # No membership at all → no features → 403.
    post "/api/v1/ai/speech",
         params: { text: "Hi" },
         headers: { "X-User-Id" => other.id.to_s }
    expect(response).to have_http_status(:forbidden)
  end

  it "200s for a Basic-tier learner (study only) — used by the 핵심 표현 듣기 button" do
    allow_any_instance_of(ElevenLabsClient).to receive(:synthesize).and_return("\x00".b)

    basic_user = create(:user)
    create(:membership, user: basic_user, membership_plan: create(:basic_plan))

    post "/api/v1/ai/speech",
         params: { text: "Could I take a look at that?" },
         headers: { "X-User-Id" => basic_user.id.to_s }
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to start_with("audio/mpeg")
  end
end

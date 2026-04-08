require "rails_helper"

RSpec.describe "POST /api/v1/ai/speech", type: :request do
  let(:user) { create(:user) }
  before do
    create(:membership, user: user, membership_plan: create(:premium_plan))
    stub_const("ENV", ENV.to_h.merge("ELEVENLABS_API_KEY" => "test-key"))
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

  it "403s without the talk feature" do
    other = create(:user)
    create(:membership, user: other, membership_plan: create(:basic_plan))

    post "/api/v1/ai/speech",
         params: { text: "Hi" },
         headers: { "X-User-Id" => other.id.to_s }
    expect(response).to have_http_status(:forbidden)
  end
end

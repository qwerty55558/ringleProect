require "rails_helper"

RSpec.describe "POST /api/v1/ai/transcriptions", type: :request do
  let(:user) { create(:user) }

  before do
    create(:membership, user: user, membership_plan: create(:premium_plan))
  end

  it "returns the transcription text from the Gemini client" do
    fake = instance_double(GeminiClient, transcribe: "hello world")
    allow(GeminiClient).to receive(:new).and_return(fake)

    file = Rack::Test::UploadedFile.new(StringIO.new("fake-bytes"), "audio/webm", original_filename: "clip.webm")
    post "/api/v1/ai/transcriptions",
         params: { audio: file },
         headers: { "X-User-Id" => user.id.to_s }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["text"]).to eq("hello world")
  end

  it "502s when the Gemini client raises" do
    allow_any_instance_of(GeminiClient).to receive(:transcribe).and_raise(GeminiClient::Error, "boom")
    file = Rack::Test::UploadedFile.new(StringIO.new("fake"), "audio/webm", original_filename: "x.webm")

    post "/api/v1/ai/transcriptions",
         params: { audio: file },
         headers: { "X-User-Id" => user.id.to_s }

    expect(response).to have_http_status(:bad_gateway)
  end
end

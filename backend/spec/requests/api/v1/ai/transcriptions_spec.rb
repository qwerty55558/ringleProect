require "rails_helper"

RSpec.describe "POST /api/v1/ai/transcriptions", type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "X-User-Id" => user.id.to_s } }

  before do
    create(:membership, user: user, membership_plan: create(:premium_plan))
  end

  it "returns the transcription text from the Gemini client and reports cache miss" do
    fake = instance_double(GeminiClient, transcribe: "hello world")
    allow(GeminiClient).to receive(:new).and_return(fake)

    file = Rack::Test::UploadedFile.new(StringIO.new("fake-bytes"), "audio/webm", original_filename: "clip.webm")
    post "/api/v1/ai/transcriptions", params: { audio: file }, headers: headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["text"]).to eq("hello world")
    expect(body["cache"]).to eq("miss")
    expect(response.headers["X-Stt-Cache"]).to eq("miss")
  end

  it "serves the cache on the second submission of identical bytes" do
    fake = instance_double(GeminiClient, transcribe: "cached!")
    allow(GeminiClient).to receive(:new).and_return(fake)

    bytes = "deterministic-bytes"
    file1 = Rack::Test::UploadedFile.new(StringIO.new(bytes), "audio/wav", original_filename: "x.wav")
    post "/api/v1/ai/transcriptions", params: { audio: file1 }, headers: headers

    file2 = Rack::Test::UploadedFile.new(StringIO.new(bytes), "audio/wav", original_filename: "x.wav")
    post "/api/v1/ai/transcriptions", params: { audio: file2 }, headers: headers

    expect(response.headers["X-Stt-Cache"]).to eq("hit")
    expect(fake).to have_received(:transcribe).once
    expect(SttArtifact.count).to eq(1)
  end

  it "hits the cache for any seeded fixture without calling Gemini" do
    Stt::FixtureSeed.call
    fixture = Stt::FixtureLibrary.all.first
    file = Rack::Test::UploadedFile.new(
      StringIO.new(fixture[:audio_bytes]),
      "audio/wav",
      original_filename: "fixture.wav"
    )
    fake = instance_double(GeminiClient)
    allow(fake).to receive(:transcribe) # spy
    allow(GeminiClient).to receive(:new).and_return(fake)

    post "/api/v1/ai/transcriptions", params: { audio: file }, headers: headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["text"]).to eq(fixture[:text])
    expect(body["cache"]).to eq("hit")
    expect(fake).not_to have_received(:transcribe)
  end

  it "502s when the Gemini client raises on a cache miss" do
    allow_any_instance_of(GeminiClient).to receive(:transcribe).and_raise(GeminiClient::Error, "boom")
    file = Rack::Test::UploadedFile.new(StringIO.new("fresh-bytes"), "audio/webm", original_filename: "x.webm")

    post "/api/v1/ai/transcriptions", params: { audio: file }, headers: headers

    expect(response).to have_http_status(:bad_gateway)
  end
end

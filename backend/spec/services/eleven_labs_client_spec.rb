require "rails_helper"

RSpec.describe ElevenLabsClient do
  let(:api_key) { "test-key" }

  before { described_class.cached_voice_id = nil }

  it "raises ConfigurationError without an API key" do
    stub_const("ENV", ENV.to_h.merge("ELEVENLABS_API_KEY" => nil))
    expect { described_class.new }.to raise_error(ElevenLabsClient::ConfigurationError)
  end

  it "uses an explicit voice_id when provided and skips the /v1/voices lookup" do
    voice = "explicit_voice_id"
    stub = stub_request(:post, "https://api.elevenlabs.io/v1/text-to-speech/#{voice}")
      .to_return(status: 200, body: "MP3", headers: { "Content-Type" => "audio/mpeg" })

    out = described_class.new(api_key: api_key, voice_id: voice).synthesize(text: "Hi")
    expect(out).to eq("MP3")
    expect(stub).to have_been_requested
    expect(WebMock).not_to have_requested(:get, %r{api\.elevenlabs\.io/v1/voices})
  end

  it "looks up the first usable voice via /v1/voices when none is configured" do
    stub_request(:get, "https://api.elevenlabs.io/v1/voices")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { voices: [{ voice_id: "discovered_voice", labels: { language: "en" } }] }.to_json
      )
    post_stub = stub_request(:post, "https://api.elevenlabs.io/v1/text-to-speech/discovered_voice")
      .to_return(status: 200, body: "MP3", headers: { "Content-Type" => "audio/mpeg" })

    out = described_class.new(api_key: api_key).synthesize(text: "Hi")
    expect(out).to eq("MP3")
    expect(post_stub).to have_been_requested
  end

  it "caches the resolved voice id across instances" do
    stub_request(:get, "https://api.elevenlabs.io/v1/voices")
      .to_return(status: 200, body: { voices: [{ voice_id: "cached" }] }.to_json,
                 headers: { "Content-Type" => "application/json" })
    stub_request(:post, "https://api.elevenlabs.io/v1/text-to-speech/cached")
      .to_return(status: 200, body: "MP3", headers: { "Content-Type" => "audio/mpeg" })

    described_class.new(api_key: api_key).synthesize(text: "first")
    described_class.new(api_key: api_key).synthesize(text: "second")

    expect(WebMock).to have_requested(:get, "https://api.elevenlabs.io/v1/voices").once
  end

  it "raises Error on a non-2xx synth response" do
    stub_request(:post, %r{api\.elevenlabs\.io/v1/text-to-speech/.+})
      .to_return(status: 401, body: "unauthorized")

    expect {
      described_class.new(api_key: api_key, voice_id: "v").synthesize(text: "Hi")
    }.to raise_error(ElevenLabsClient::Error, /401/)
  end
end

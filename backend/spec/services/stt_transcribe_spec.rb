require "rails_helper"

RSpec.describe Stt::Transcribe do
  let(:fake_client) { instance_double(GeminiClient) }

  before do
    allow(fake_client).to receive(:transcribe).and_return("hello world")
  end

  it "calls Gemini once and persists the result on the first request" do
    res = described_class.call(audio_bytes: "abc".b, mime_type: "audio/wav", client: fake_client)
    expect(res.cache_hit).to be(false)
    expect(res.text).to eq("hello world")
    expect(SttArtifact.count).to eq(1)
    expect(res.artifact.audio).to be_attached
  end

  it "serves the cached transcription on the second request without re-calling Gemini" do
    described_class.call(audio_bytes: "abc".b, mime_type: "audio/wav", client: fake_client)
    expect(fake_client).to have_received(:transcribe).once

    second = described_class.call(audio_bytes: "abc".b, mime_type: "audio/wav", client: fake_client)
    expect(fake_client).to have_received(:transcribe).once # still 1
    expect(second.cache_hit).to be(true)
    expect(second.text).to eq("hello world")
  end

  it "treats different bytes as separate cache entries" do
    described_class.call(audio_bytes: "one".b, mime_type: "audio/wav", client: fake_client)
    described_class.call(audio_bytes: "two".b, mime_type: "audio/wav", client: fake_client)
    expect(SttArtifact.count).to eq(2)
    expect(fake_client).to have_received(:transcribe).twice
  end

  it "rejects empty audio" do
    expect { described_class.call(audio_bytes: "".b, mime_type: "audio/wav", client: fake_client) }
      .to raise_error(ArgumentError)
  end
end

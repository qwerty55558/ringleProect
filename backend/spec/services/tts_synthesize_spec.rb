require "rails_helper"

RSpec.describe Tts::Synthesize do
  let(:fake_client) do
    instance_double(ElevenLabsClient, voice_id: "voice_x").tap do |c|
      allow(c).to receive(:instance_variable_get).with(:@model_id).and_return("model_x")
    end
  end

  before do
    allow(fake_client).to receive(:synthesize).with(text: "Hello").and_return("\xFFmp3bytes".b)
  end

  it "calls ElevenLabs once and persists the result on the first request" do
    res = described_class.call(text: "Hello", client: fake_client)
    expect(res.cache_hit).to be(false)
    expect(res.bytes).to eq("\xFFmp3bytes".b)
    expect(TtsArtifact.count).to eq(1)
    expect(res.artifact.audio).to be_attached
  end

  it "serves the cached blob without re-calling ElevenLabs on the second request" do
    described_class.call(text: "Hello", client: fake_client)
    expect(fake_client).to have_received(:synthesize).once

    second = described_class.call(text: "Hello", client: fake_client)
    expect(fake_client).to have_received(:synthesize).once # still 1
    expect(second.cache_hit).to be(true)
    expect(second.bytes).to eq("\xFFmp3bytes".b)
  end

  it "rejects blank input" do
    expect { described_class.call(text: "  ", client: fake_client) }.to raise_error(ArgumentError)
  end
end

require "rails_helper"

RSpec.describe Stt::FixtureLibrary do
  describe ".synth_wav" do
    it "produces a valid 16-bit mono PCM WAV header" do
      bytes = described_class.synth_wav(tone_hz: 220.0, duration_ms: 100)
      expect(bytes[0, 4]).to eq("RIFF")
      expect(bytes[8, 4]).to eq("WAVE")
      expect(bytes[12, 4]).to eq("fmt ")
      # data chunk follows the header (44 bytes total)
      expect(bytes[36, 4]).to eq("data")
    end

    it "is byte-deterministic for the same args" do
      a = described_class.synth_wav(tone_hz: 220.0, duration_ms: 100)
      b = described_class.synth_wav(tone_hz: 220.0, duration_ms: 100)
      expect(a).to eq(b)
    end

    it "produces distinct bytes for different frequencies" do
      a = described_class.synth_wav(tone_hz: 220.0, duration_ms: 100)
      b = described_class.synth_wav(tone_hz: 440.0, duration_ms: 100)
      expect(a).not_to eq(b)
    end
  end

  describe ".all" do
    it "returns one entry per fixture with audio bytes" do
      entries = described_class.all
      expect(entries.length).to eq(described_class::FIXTURES.length)
      entries.each do |e|
        expect(e[:slug]).to be_present
        expect(e[:text]).to be_present
        expect(e[:audio_bytes].bytesize).to be > 100
      end
    end
  end
end

RSpec.describe Stt::FixtureSeed do
  it "creates one row per fixture and is idempotent" do
    expect { described_class.call }.to change(SttArtifact.fixtures, :count).by(Stt::FixtureLibrary::FIXTURES.length)
    expect { described_class.call }.not_to change(SttArtifact.fixtures, :count)
  end

  it "stores the seeded text under the matching audio hash" do
    described_class.call
    fixture = Stt::FixtureLibrary.all.first
    hash = SttArtifact.hash_for(fixture[:audio_bytes])
    artifact = SttArtifact.find_by(audio_hash: hash)
    expect(artifact.text).to eq(fixture[:text])
    expect(artifact.slug).to eq(fixture[:slug])
  end

  it "drives the Stt::Transcribe cache to a hit when called with the same fixture bytes" do
    described_class.call
    fixture = Stt::FixtureLibrary.all.first
    fake = instance_double(GeminiClient)
    res = Stt::Transcribe.call(audio_bytes: fixture[:audio_bytes], mime_type: "audio/wav", client: fake)
    expect(res.cache_hit).to be(true)
    expect(res.text).to eq(fixture[:text])
    expect(fake).not_to have_received(:transcribe) if fake.respond_to?(:received_messages)
  end
end

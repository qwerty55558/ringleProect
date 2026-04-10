require "rails_helper"

RSpec.describe GeminiClient do
  let(:client) { described_class.new(api_key: "test") }

  describe "#chat safety block detection" do
    def stub_response(body)
      conn = Faraday.new do |b|
        b.adapter :test do |s|
          s.post(%r{models/.*:generateContent}) { [200, { "Content-Type" => "application/json" }, body.to_json] }
        end
      end
      described_class.new(api_key: "test", conn: conn)
    end

    it "raises SafetyBlocked on candidate finishReason=SAFETY" do
      c = stub_response(
        candidates: [{ content: { parts: [{ text: "" }] }, finishReason: "SAFETY" }]
      )
      expect { c.chat(messages: [{ role: "user", text: "hi" }]) }
        .to raise_error(GeminiClient::SafetyBlocked, /SAFETY/)
    end

    it "raises SafetyBlocked on promptFeedback.blockReason" do
      c = stub_response(
        promptFeedback: { blockReason: "SAFETY" },
        candidates: []
      )
      expect { c.chat(messages: [{ role: "user", text: "hi" }]) }
        .to raise_error(GeminiClient::SafetyBlocked, /blocked/)
    end

    it "passes through normal completions" do
      c = stub_response(candidates: [{ content: { parts: [{ text: "hello" }] }, finishReason: "STOP" }])
      expect(c.chat(messages: [{ role: "user", text: "hi" }])).to eq("hello")
    end
  end

  describe "#build_chat_body" do
    it "always injects safetySettings into the request body" do
      body = client.send(:build_chat_body, messages: [{ role: "user", text: "hi" }], system_instruction: nil)
      expect(body[:safetySettings]).to be_an(Array)
      categories = body[:safetySettings].map { |s| s[:category] }
      expect(categories).to include(
        "HARM_CATEGORY_HARASSMENT",
        "HARM_CATEGORY_HATE_SPEECH",
        "HARM_CATEGORY_SEXUALLY_EXPLICIT",
        "HARM_CATEGORY_DANGEROUS_CONTENT"
      )
    end
  end

  describe "#transcribe fallback chain" do
    def make_client(responses_by_model)
      conn = Faraday.new do |b|
        b.adapter :test do |s|
          s.post(%r{models/(.+):generateContent}) do |env|
            model = env.url.path[%r{models/(.+):generateContent}, 1]
            status, body = responses_by_model.fetch(model, [404, { error: "not found" }])
            [status, { "Content-Type" => "application/json" }, body.to_json]
          end
        end
      end
      described_class.new(api_key: "test", conn: conn)
    end

    let(:ok_body) { { candidates: [{ content: { parts: [{ text: "hello world" }] }, finishReason: "STOP" }] } }

    it "returns the result from the first model that succeeds" do
      c = make_client("gemini-2.5-flash" => [200, ok_body])
      expect(c.transcribe(audio_bytes: "x", mime_type: "audio/wav", models: %w[gemini-2.5-flash])).to eq("hello world")
    end

    it "falls through 429s to the next model in the chain" do
      c = make_client(
        "gemini-2.5-flash"      => [429, { error: "quota" }],
        "gemini-2.0-flash"      => [429, { error: "quota" }],
        "gemini-2.0-flash-lite" => [200, ok_body]
      )
      result = c.transcribe(
        audio_bytes: "x", mime_type: "audio/wav",
        models: %w[gemini-2.5-flash gemini-2.0-flash gemini-2.0-flash-lite]
      )
      expect(result).to eq("hello world")
    end

    it "raises when every model in the chain fails with a retryable status" do
      c = make_client(
        "a" => [429, { error: "quota" }],
        "b" => [503, { error: "overloaded" }]
      )
      expect {
        c.transcribe(audio_bytes: "x", mime_type: "audio/wav", models: %w[a b])
      }.to raise_error(GeminiClient::Error, /all STT models exhausted/)
    end

    it "raises immediately on a non-retryable status (e.g. 400)" do
      c = make_client("bad" => [400, { error: "bad request" }])
      expect {
        c.transcribe(audio_bytes: "x", mime_type: "audio/wav", models: %w[bad])
      }.to raise_error(GeminiClient::Error, /400/)
    end

    it "falls through SafetyBlocked to the next model" do
      safety_body = { candidates: [{ content: { parts: [{ text: "" }] }, finishReason: "SAFETY" }] }
      c = make_client(
        "gemini-2.5-flash" => [200, safety_body],
        "gemini-2.0-flash" => [200, ok_body]
      )
      result = c.transcribe(
        audio_bytes: "x", mime_type: "audio/wav",
        models: %w[gemini-2.5-flash gemini-2.0-flash]
      )
      expect(result).to eq("hello world")
    end

    it "raises when every model is safety-blocked" do
      safety_body = { candidates: [{ content: { parts: [{ text: "" }] }, finishReason: "SAFETY" }] }
      c = make_client(
        "a" => [200, safety_body],
        "b" => [200, safety_body]
      )
      expect {
        c.transcribe(audio_bytes: "x", mime_type: "audio/wav", models: %w[a b])
      }.to raise_error(GeminiClient::Error, /all STT models exhausted/)
    end

    it "falls through promptFeedback blockReason to the next model" do
      blocked_body = { promptFeedback: { blockReason: "SAFETY" }, candidates: [] }
      c = make_client(
        "a" => [200, blocked_body],
        "b" => [200, ok_body]
      )
      result = c.transcribe(audio_bytes: "x", mime_type: "audio/wav", models: %w[a b])
      expect(result).to eq("hello world")
    end
  end
end

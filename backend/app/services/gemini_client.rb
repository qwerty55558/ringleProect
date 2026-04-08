require "faraday"
require "base64"
require "json"

# Thin wrapper around Google's Generative Language (Gemini) HTTP API.
# We intentionally keep this client transport-only — feature-specific shaping
# (system prompts, message conversion) lives in the calling service so the
# client stays easy to stub in tests.
class GeminiClient
  BASE_URL = "https://generativelanguage.googleapis.com/v1beta".freeze

  # Free-tier models. We deliberately split chat and STT across two
  # different model families so each draws from its own per-model RPD
  # bucket (otherwise a single 20 RPD bucket caps the demo at ~10 turns).
  #
  #   gemini-2.5-flash      — LLM chat, streaming. GA, well-supported on
  #                           v1beta `:streamGenerateContent`.
  #   gemini-2.0-flash-lite — multimodal STT (audio → text). GA, accepts
  #                           inline audio data and is on a separate RPD
  #                           bucket from gemini-2.5-flash. We previously
  #                           tried `gemini-2.5-flash-lite` here but it
  #                           404s on `:generateContent` even though it
  #                           shows up in the AI Studio quota dashboard.
  DEFAULT_CHAT_MODEL  = "gemini-2.5-flash".freeze
  DEFAULT_AUDIO_MODEL = "gemini-2.0-flash-lite".freeze

  class Error < StandardError; end
  class ConfigurationError < Error; end

  def initialize(api_key: ENV["GEMINI_API_KEY"], conn: nil)
    raise ConfigurationError, "GEMINI_API_KEY is not set" if api_key.blank?

    @api_key = api_key
    @conn = conn || build_conn
  end

  # Streaming chat completion. Yields each text delta as it arrives so the
  # controller can forward it directly over SSE.
  #
  # `messages` is an array of { role: "user"|"model", text: "..." }.
  # `system_instruction` is an optional string seed prompt.
  def stream_chat(messages:, system_instruction: nil, model: DEFAULT_CHAT_MODEL, &block)
    body = build_chat_body(messages: messages, system_instruction: system_instruction)
    path = "/models/#{model}:streamGenerateContent"

    @conn.post(path, body.to_json, request_headers.merge("Accept" => "application/json")) do |req|
      req.params["alt"] = "sse"
      req.options.on_data = proc { |chunk, _| handle_sse_chunk(chunk, &block) }
    end
  end

  # Non-streaming chat — primarily used by specs and as a fallback path
  # when the controller can't use ActionController::Live (e.g. test env).
  def chat(messages:, system_instruction: nil, model: DEFAULT_CHAT_MODEL)
    body = build_chat_body(messages: messages, system_instruction: system_instruction)
    res = @conn.post("/models/#{model}:generateContent", body.to_json, request_headers)
    raise_on_error!(res)
    extract_text(JSON.parse(res.body))
  end

  # Speech-to-text. Pass raw audio bytes plus its mime type. We send it as
  # base64 inline_data to a multimodal Gemini model with a transcription
  # instruction — this avoids needing a separate STT product/API key.
  def transcribe(audio_bytes:, mime_type:, model: DEFAULT_AUDIO_MODEL)
    body = {
      contents: [{
        role: "user",
        parts: [
          { text: "Transcribe the user's spoken audio verbatim. Reply with only the transcription text." },
          { inline_data: { mime_type: mime_type, data: Base64.strict_encode64(audio_bytes) } }
        ]
      }],
      generationConfig: { temperature: 0 }
    }
    res = @conn.post("/models/#{model}:generateContent", body.to_json, request_headers)
    raise_on_error!(res)
    extract_text(JSON.parse(res.body)).strip
  end

  private

  def build_conn
    Faraday.new(url: BASE_URL) do |f|
      f.options.timeout = 60
      f.adapter Faraday.default_adapter
    end
  end

  def request_headers
    { "Content-Type" => "application/json", "x-goog-api-key" => @api_key }
  end

  def build_chat_body(messages:, system_instruction:)
    body = {
      contents: messages.map do |m|
        { role: m[:role] || m["role"], parts: [{ text: m[:text] || m["text"] }] }
      end,
      generationConfig: { temperature: 0.7 }
    }
    if system_instruction.present?
      body[:systemInstruction] = { role: "system", parts: [{ text: system_instruction }] }
    end
    body
  end

  def raise_on_error!(res)
    return if res.success?

    raise Error, "Gemini API error #{res.status}: #{res.body[0..500]}"
  end

  def extract_text(parsed)
    parsed.dig("candidates", 0, "content", "parts")&.filter_map { |p| p["text"] }&.join("") || ""
  end

  # Gemini SSE chunks are line-oriented `data: { ... }` blocks; we accumulate
  # across partial chunks and yield the text deltas as they arrive.
  def handle_sse_chunk(chunk, &block)
    @sse_buffer ||= +""
    @sse_buffer << chunk
    while (idx = @sse_buffer.index("\n"))
      line = @sse_buffer.slice!(0, idx + 1).chomp
      next unless line.start_with?("data: ")

      payload = line.sub("data: ", "")
      next if payload.blank? || payload == "[DONE]"

      begin
        json = JSON.parse(payload)
        text = extract_text(json)
        block.call(text) if text.present?
      rescue JSON::ParserError
        # partial frame — Faraday will deliver the rest in the next chunk
      end
    end
  end
end

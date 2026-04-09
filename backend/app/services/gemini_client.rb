require "faraday"
require "base64"
require "json"

# Thin wrapper around Google's Generative Language (Gemini) HTTP API.
# We intentionally keep this client transport-only — feature-specific shaping
# (system prompts, message conversion) lives in the calling service so the
# client stays easy to stub in tests.
class GeminiClient
  # NOTE: trailing slash is mandatory. Faraday treats any request path
  # that starts with `/` as absolute and *replaces* the BASE_URL path
  # entirely — meaning `@conn.post("/models/...")` against a BASE_URL
  # without a trailing slash silently strips `/v1beta` from the URL and
  # we get a 404 from Gemini. We pair this with leading-slash-free paths
  # below (e.g. `"models/...":streamGenerateContent`).
  BASE_URL = "https://generativelanguage.googleapis.com/v1beta/".freeze

  DEFAULT_CHAT_MODEL = "gemini-2.5-flash".freeze

  # Ordered fallback chain for STT. transcribe() walks these in order
  # and skips any that 429/404/5xx. The stt_artifacts lazy cache means
  # repeat audio bytes only burn the chain once.
  STT_MODEL_CHAIN = %w[
    gemini-2.5-flash
    gemini-2.0-flash
    gemini-2.0-flash-lite
    gemini-1.5-flash
  ].freeze

  RETRYABLE_STATUSES = [403, 404, 429, 500, 502, 503, 504].freeze

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class SafetyBlocked < Error; end

  SAFETY_SETTINGS = [
    { category: "HARM_CATEGORY_HARASSMENT",        threshold: "BLOCK_MEDIUM_AND_ABOVE" },
    { category: "HARM_CATEGORY_HATE_SPEECH",       threshold: "BLOCK_MEDIUM_AND_ABOVE" },
    { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_MEDIUM_AND_ABOVE" },
    { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_MEDIUM_AND_ABOVE" }
  ].freeze

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
    path = "models/#{model}:streamGenerateContent"

    # Buffer for the on_data callback so a non-200 response (e.g. a
    # JSON-formatted 429 quota error) can be surfaced as a
    # GeminiClient::Error after the request finishes — without it,
    # `on_data` was silently swallowing the error body and we returned
    # a "successful" stream with zero deltas.
    error_body_buffer = +""
    sse_buffer = +""
    safety_state = { block_reason: nil, finish_reason: nil }

    response = @conn.post(path, body.to_json, request_headers.merge("Accept" => "application/json")) do |req|
      req.params["alt"] = "sse"
      req.options.on_data = proc do |chunk, _|
        error_body_buffer << chunk if error_body_buffer.bytesize < 1024
        handle_sse_chunk(sse_buffer, chunk, safety_state, &block)
      end
    end

    unless response.success?
      raise Error, "Gemini API error #{response.status}: #{error_body_buffer.byteslice(0, 500)}"
    end

    if safety_state[:block_reason]
      raise SafetyBlocked, "prompt blocked: #{safety_state[:block_reason]}"
    end
    if safety_state[:finish_reason] == "SAFETY"
      raise SafetyBlocked, "response blocked: SAFETY"
    end
  end

  # Non-streaming chat — primarily used by specs and as a fallback path
  # when the controller can't use ActionController::Live (e.g. test env).
  def chat(messages:, system_instruction: nil, model: DEFAULT_CHAT_MODEL)
    body = build_chat_body(messages: messages, system_instruction: system_instruction)
    res = @conn.post("models/#{model}:generateContent", body.to_json, request_headers)
    raise_on_error!(res)
    parsed = JSON.parse(res.body)
    detect_safety_block!(parsed)
    extract_text(parsed)
  end

  def transcribe(audio_bytes:, mime_type:, models: STT_MODEL_CHAIN)
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

    last_error = nil
    models.each do |model|
      res = @conn.post("models/#{model}:generateContent", body.to_json, request_headers)
      if res.success?
        parsed = JSON.parse(res.body)
        begin
          detect_safety_block!(parsed)
        rescue SafetyBlocked => e
          last_error = "#{model} safety: #{e.message}"
          Rails.logger.warn("[gemini] STT #{model} → safety blocked, trying next") if defined?(Rails)
          next
        end
        Rails.logger.info("[gemini] STT ok: #{model}") if defined?(Rails)
        return extract_text(parsed).strip
      elsif RETRYABLE_STATUSES.include?(res.status)
        last_error = "#{model} #{res.status}"
        Rails.logger.warn("[gemini] STT #{model} → #{res.status}, trying next") if defined?(Rails)
        next
      else
        raise Error, "Gemini API error #{res.status}: #{res.body[0..500]}"
      end
    end

    raise Error, "all STT models exhausted: #{last_error}"
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
      generationConfig: { temperature: 0.7 },
      safetySettings: SAFETY_SETTINGS
    }
    if system_instruction.present?
      body[:systemInstruction] = { role: "system", parts: [{ text: system_instruction }] }
    end
    body
  end

  def detect_safety_block!(parsed)
    block_reason = parsed.dig("promptFeedback", "blockReason")
    raise SafetyBlocked, "prompt blocked: #{block_reason}" if block_reason

    finish = parsed.dig("candidates", 0, "finishReason")
    raise SafetyBlocked, "response blocked: #{finish}" if finish == "SAFETY"
  end

  def raise_on_error!(res)
    return if res.success?

    raise Error, "Gemini API error #{res.status}: #{res.body[0..500]}"
  end

  def extract_text(parsed)
    parsed.dig("candidates", 0, "content", "parts")&.filter_map { |p| p["text"] }&.join("") || ""
  end

  def handle_sse_chunk(buffer, chunk, safety_state, &block)
    buffer << chunk
    while (idx = buffer.index("\n"))
      line = buffer.slice!(0, idx + 1).chomp
      next unless line.start_with?("data: ")

      payload = line.sub("data: ", "")
      next if payload.blank? || payload == "[DONE]"

      begin
        json = JSON.parse(payload)
        safety_state[:block_reason]  ||= json.dig("promptFeedback", "blockReason")
        safety_state[:finish_reason] ||= json.dig("candidates", 0, "finishReason")
        text = extract_text(json)
        block.call(text) if text.present?
      rescue JSON::ParserError
        # partial frame — next chunk will complete it
      end
    end
  end
end

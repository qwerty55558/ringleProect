require "faraday"
require "json"

# ElevenLabs Text-to-Speech client.
#
# Picked over Gemini TTS / Cloud TTS / Web Speech because:
#   - Free tier: 10K chars/month with no credit card
#   - Voice quality is dramatically better than browser/Mac defaults —
#     Rachel/Adam sound essentially human
#   - `eleven_turbo_v2_5` model is sub-second latency in practice, which
#     matters for the conversational UX
#
# Returns raw MP3 bytes; the browser <audio> tag plays them directly.
class ElevenLabsClient
  BASE_URL = "https://api.elevenlabs.io".freeze

  # NOTE: free-tier accounts can't call library voices like Rachel
  # (`21m00Tcm4TlvDq8ikWAM`) — the API returns 402 paid_plan_required.
  # We resolve a usable voice id at runtime by hitting GET /v1/voices,
  # which returns whatever voices the account has access to (every free
  # account gets a handful of starter samples). The result is cached on
  # the class so we only pay one round-trip per process.
  DEFAULT_MODEL_ID = "eleven_turbo_v2_5".freeze

  class Error < StandardError; end
  class ConfigurationError < Error; end

  @cached_voice_id = nil

  class << self
    attr_accessor :cached_voice_id
  end

  def initialize(api_key: ENV["ELEVENLABS_API_KEY"], voice_id: nil, model_id: nil, conn: nil)
    raise ConfigurationError, "ELEVENLABS_API_KEY is not set" if api_key.blank?

    @api_key  = api_key
    @voice_id = voice_id || ENV["ELEVENLABS_VOICE_ID"].presence
    @model_id = model_id || ENV["ELEVENLABS_MODEL_ID"].presence || DEFAULT_MODEL_ID
    @conn = conn || Faraday.new(url: BASE_URL) { |f| f.options.timeout = 60; f.adapter Faraday.default_adapter }
  end

  # Returns a voice id usable by this account. Cached after the first call
  # so we only hit /v1/voices once per process.
  def voice_id
    return @voice_id if @voice_id.present?
    return self.class.cached_voice_id if self.class.cached_voice_id.present?

    res = @conn.get("/v1/voices") do |req|
      req.headers["xi-api-key"] = @api_key
    end
    raise Error, "ElevenLabs voices error #{res.status}: #{res.body[0..200]}" unless res.success?

    voices = JSON.parse(res.body)["voices"] || []
    # Prefer English voices when present so the tutor sounds right; fall
    # back to the first listed voice otherwise.
    chosen = voices.find { |v| (v["labels"] || {})["language"]&.start_with?("en") } ||
             voices.find { |v| v["fine_tuning"].nil? || v["fine_tuning"]["language"].nil? || v["fine_tuning"]["language"].to_s.start_with?("en") } ||
             voices.first
    raise Error, "No ElevenLabs voices available on this account" unless chosen

    self.class.cached_voice_id = chosen["voice_id"]
  end

  def synthesize(text:)
    body = {
      text: text,
      model_id: @model_id,
      voice_settings: {
        stability: 0.5,
        similarity_boost: 0.75,
        style: 0.0,
        use_speaker_boost: true
      }
    }

    res = @conn.post("/v1/text-to-speech/#{voice_id}") do |req|
      req.headers["xi-api-key"]   = @api_key
      req.headers["Content-Type"] = "application/json"
      req.headers["Accept"]       = "audio/mpeg"
      req.body = body.to_json
    end

    raise Error, "ElevenLabs error #{res.status}: #{res.body[0..400]}" unless res.success?

    res.body.b
  end
end

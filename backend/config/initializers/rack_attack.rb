# Throttle abusive use of expensive AI endpoints. The conversation page can
# burn through Gemini quota quickly if a malicious or buggy client holds the
# mic open, so we cap per-user request rates here in addition to the
# client-side guards.
class Rack::Attack
  AI_PATHS = %r{\A/api/v1/ai/}

  # Identify caller by X-User-Id header (we don't have real auth per the spec).
  # Falls back to IP so unauthenticated callers can't bypass by omitting it.
  def self.ai_caller_key(req)
    req.get_header("HTTP_X_USER_ID").presence || req.ip
  end

  throttle("ai/messages per user", limit: 20, period: 1.minute) do |req|
    ai_caller_key(req) if req.path.match?(AI_PATHS)
  end

  throttle("ai/messages per user hourly", limit: 200, period: 1.hour) do |req|
    ai_caller_key(req) if req.path.match?(AI_PATHS)
  end

  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"] || {}
    retry_after = match_data[:period] || 60
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [{ error: "rate_limited", retry_after: retry_after }.to_json]
    ]
  end
end

Rails.application.config.middleware.use Rack::Attack

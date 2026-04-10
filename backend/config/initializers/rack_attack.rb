# Throttle abusive use of expensive AI endpoints AND of long-lived SSE
# connections. Falcon's fiber model means a single fiber is cheap, but
# a malicious client could still open thousands within the 5-minute
# MAX_DURATION window — at ~few KB per fiber that's noticeable memory,
# and more importantly each one holds a Bus subscriber slot. Rate
# limiting at the edge is the right defense (Nginx would do this in a
# real prod stack; rack-attack is the in-process equivalent for the
# assignment).
class Rack::Attack
  AI_PATHS  = %r{\A/api/v1/ai/}
  # Both /me/stream and the admin variant. We separate them in the
  # throttle name so we can tune them independently if usage diverges.
  SSE_PATHS = %r{\A/api/v1/(me/stream|admin/memberships/stream|study_materials/stream|analysis/stream)\z}

  # Identify caller by X-User-Id header (we don't have real auth per the spec).
  # SSE connections also pass user_id via the query string because EventSource
  # can't set custom request headers — fall back to that, then IP.
  def self.user_caller_key(req)
    req.get_header("HTTP_X_USER_ID").presence ||
      req.params["user_id"].presence ||
      req.ip
  end

  # Backwards-compatible alias used by the existing AI throttles.
  singleton_class.send(:alias_method, :ai_caller_key, :user_caller_key)

  throttle("ai/messages per user", limit: 20, period: 1.minute) do |req|
    user_caller_key(req) if req.path.match?(AI_PATHS)
  end

  throttle("ai/messages per user hourly", limit: 200, period: 1.hour) do |req|
    user_caller_key(req) if req.path.match?(AI_PATHS)
  end

  # Cap how often a single user can OPEN a fresh SSE connection. Each
  # navigation / refresh costs one slot in this bucket. 30 / minute is
  # generous for legitimate use (the app holds the connection open for
  # the whole session) but instantly chokes a refresh-storm attacker.
  throttle("sse open per user", limit: 30, period: 1.minute) do |req|
    user_caller_key(req) if req.path.match?(SSE_PATHS)
  end

  # Second tier — also cap by IP so an attacker who rotates user_id
  # can't bypass the per-user cap.
  throttle("sse open per ip", limit: 60, period: 1.minute) do |req|
    req.ip if req.path.match?(SSE_PATHS)
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

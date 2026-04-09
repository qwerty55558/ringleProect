module Memberships
  # Admin-driven membership creation. No PG charge — the row is stamped with
  # source=admin_grant so we can audit later why a user has access without a
  # corresponding payment.
  #
  # Duration resolution (in priority order):
  #   1. explicit duration_seconds (used by the admin UI's "초" toggle —
  #      lets us grant a 30-second membership for the expiry demo)
  #   2. explicit duration_days override
  #   3. the plan's natural duration (`plan.expiry_from`)
  #
  # Both overrides are validated server-side: must be a positive integer,
  # never zero, never beyond MAX_GRANT_DAYS. The frontend mirrors the same
  # rule via `parseAdminGrantDuration` so the operator sees errors inline,
  # but this is the authoritative gate — never trust the client.
  class AdminGrant
    class InvalidDuration < StandardError; end

    MAX_GRANT_DAYS    = 100
    MAX_GRANT_SECONDS = MAX_GRANT_DAYS * 24 * 60 * 60

    def self.call(user:, plan:, duration_days: nil, duration_seconds: nil)
      now = Time.current

      # If the user already has an active membership for THIS plan,
      # stack the new duration on top of its expires_at instead of
      # creating a parallel row. Same plan-class semantics as
      # Memberships::Purchase. Different plan classes stay separate.
      existing = user.memberships
                     .where(membership_plan_id: plan.id, status: "active")
                     .where("expires_at > ?", now)
                     .order(expires_at: :desc)
                     .first

      base = existing&.expires_at || now

      new_expires_at =
        if duration_seconds.present?
          base + validated_seconds(duration_seconds).seconds
        elsif duration_days.present?
          base + validated_days(duration_days).days
        else
          plan.extend_from(base)
        end

      if existing
        existing.update!(expires_at: new_expires_at)
        existing
      else
        user.memberships.create!(
          membership_plan: plan,
          started_at: now,
          expires_at: new_expires_at,
          status: "active",
          source: "admin_grant"
        )
      end
    end

    def self.validated_days(raw)
      n = Integer(raw.to_s, exception: false)
      raise InvalidDuration, "duration_days must be a positive integer" if n.nil? || n < 1
      raise InvalidDuration, "duration_days cannot exceed #{MAX_GRANT_DAYS}" if n > MAX_GRANT_DAYS

      n
    end

    def self.validated_seconds(raw)
      n = Integer(raw.to_s, exception: false)
      raise InvalidDuration, "duration_seconds must be a positive integer" if n.nil? || n < 1
      raise InvalidDuration, "duration_seconds cannot exceed #{MAX_GRANT_SECONDS}" if n > MAX_GRANT_SECONDS

      n
    end
  end
end

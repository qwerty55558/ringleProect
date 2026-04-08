module Memberships
  # Admin-driven membership creation. No PG charge — the row is stamped with
  # source=admin_grant so we can audit later why a user has access without a
  # corresponding payment.
  class AdminGrant
    def self.call(user:, plan:, duration_days: nil)
      now = Time.current
      days = duration_days.presence || plan.duration_days
      user.memberships.create!(
        membership_plan: plan,
        started_at: now,
        expires_at: now + days.to_i.days,
        status: "active",
        source: "admin_grant"
      )
    end
  end
end

class AddDurationSecondsToMembershipPlans < ActiveRecord::Migration[7.2]
  def change
    # Sub-day plans (e.g. the 30-second expiry plan we ship for demo /
    # expiration testing) need finer granularity than `duration_days`.
    # Nullable so the existing day-based plans keep working unchanged —
    # the model picks `duration_seconds` over `duration_days` only when
    # it's present.
    add_column :membership_plans, :duration_seconds, :integer
  end
end

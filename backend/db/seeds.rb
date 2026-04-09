# Idempotent seed data for development and demos.
#
# Creates:
#   - 1 admin user (id 1) and 2 regular users (ids 2, 3)
#   - 2 membership plans (Basic / Premium Plus)
#   - hand-curated study materials for the curriculum tab
#
# The admin UI exposes a "단위: 일 / 초" toggle on the duration override
# field, so the 30-second expiry simulation is achievable on top of any
# existing plan — no dedicated demo plan needed.
#
# Use the X-User-Id header in requests to act as a given user.

admin = User.find_or_create_by!(email: "admin@ringle.test") do |u|
  u.name = "Ringle Admin"
  u.role = "admin"
end

learner = User.find_or_create_by!(email: "learner@ringle.test") do |u|
  u.name = "Danny Learner"
  u.role = "user"
end

newcomer = User.find_or_create_by!(email: "newcomer@ringle.test") do |u|
  u.name = "Alex Newcomer"
  u.role = "user"
end

basic = MembershipPlan.find_or_create_by!(name: "Basic") do |p|
  p.price_cents     = 129_000_00
  p.duration_days   = 30
  p.features        = %w[study]
  p.active          = true
end

premium = MembershipPlan.find_or_create_by!(name: "Premium Plus") do |p|
  p.price_cents     = 219_000_00
  p.duration_days   = 60
  p.features        = %w[study talk analysis]
  p.active          = true
end

study_count   = StudyMaterials::CurriculumSeed.call
fixture_count = Stt::FixtureSeed.call

puts "Seeded users: admin=#{admin.id}, learner=#{learner.id}, newcomer=#{newcomer.id}"
puts "Seeded plans: #{MembershipPlan.pluck(:name).join(', ')}"
puts "Seeded study materials: #{study_count}"
puts "Seeded STT fixtures: #{fixture_count}"

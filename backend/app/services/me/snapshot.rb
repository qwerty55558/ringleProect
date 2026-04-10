module Me
  class Snapshot
    def self.call(user)
      memberships = user.memberships.includes(:membership_plan).to_a
      {
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          role: user.role
        },
        memberships: memberships.map { |m| serialize_membership(m) },
        features: user.available_features,
        server_time: Time.current.iso8601(3),
        study_generations: {
          used: user.study_generations_used,
          limit: StudyMaterials::Generate::MAX_PER_USER,
          remaining: [StudyMaterials::Generate::MAX_PER_USER - user.study_generations_used, 0].max,
          profanity_offenses: user.study_profanity_offenses,
          penalty_interval: StudyMaterials::Generate::PROFANITY_PENALTY_INTERVAL
        }
      }
    end

    def self.serialize_membership(m)
      {
        id: m.id,
        plan: { id: m.membership_plan.id, name: m.membership_plan.name, features: m.membership_plan.features },
        state: m.state,
        source: m.source,
        started_at: m.started_at.iso8601,
        expires_at: m.expires_at.iso8601
      }
    end
  end
end

module StudyMaterials
  # Admin-only "nuke and reseed" path for the study curriculum. Powers
  # the dev panel's "커리큘럼 리셋" button.
  #
  # Steps:
  #   1. Delete every AI-generated row (the seeded ones get refreshed
  #      in step 3 below). We don't touch payments / memberships /
  #      conversations — only the curriculum table.
  #   2. Reset every user's `study_generations_used` counter so they
  #      get their 3-slot quota back.
  #   3. Re-run `CurriculumSeed.call` to materialise any new SEED
  #      rows (`find_or_initialize_by(:slug)` makes this idempotent).
  #   4. Publish to `Study::Bus` so every open
  #      /api/v1/study_materials/stream subscriber repaints. The
  #      effect is "everyone's /study tab refreshes at once".
  #
  # Wrapped in a transaction so a partial failure leaves the curriculum
  # alone instead of half-wiped.
  class Reset
    def self.call
      counts = ActiveRecord::Base.transaction do
        deleted = StudyMaterial.where(ai_generated: true).delete_all
        counter_resets = User.where("study_generations_used > 0 OR study_profanity_offenses > 0")
                             .update_all(study_generations_used: 0, study_profanity_offenses: 0)
        seeded = CurriculumSeed.call
        { deleted_ai_rows: deleted, user_counters_reset: counter_resets, seeded: seeded }
      end

      Study::Bus.publish
      counts
    end
  end
end

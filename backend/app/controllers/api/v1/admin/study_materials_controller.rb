module Api
  module V1
    module Admin
      # Admin-only nuke-and-reseed for the study curriculum. Lives
      # under the admin namespace because the dev panel button is
      # gated to admin accounts and we don't want regular study
      # users discovering this endpoint.
      class StudyMaterialsController < ApplicationController
        before_action :require_user!

        # Full reset: wipe AI rows + reset counters + re-run seed.
        def reset
          counts = ::StudyMaterials::Reset.call
          render json: {
            ok: true,
            deleted_ai_rows: counts[:deleted_ai_rows],
            user_counters_reset: counts[:user_counters_reset],
            seeded: counts[:seeded]
          }
        end

        # Targeted delete: wipe ONLY AI-generated rows. Leaves the
        # seeded curriculum and per-user generation counters alone —
        # the use case is "the AI pool got stale or weird, clean it
        # up without forcing every learner back to 3 fresh slots".
        # Publishes via Study::Bus so every open /study tab repaints.
        def destroy_ai_generated
          deleted = StudyMaterial.where(ai_generated: true).delete_all
          ::Study::Bus.publish
          render json: { ok: true, deleted: deleted }
        end

        def reset_generation_counters
          affected = User.where("study_generations_used > 0 OR study_profanity_offenses > 0")
          ids = affected.pluck(:id)
          count = affected.update_all(study_generations_used: 0, study_profanity_offenses: 0)
          ids.each { |id| ::Me::Bus.publish(id) }
          render json: { ok: true, users_reset: count }
        end
      end
    end
  end
end

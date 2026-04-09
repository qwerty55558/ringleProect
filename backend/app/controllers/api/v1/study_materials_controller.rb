module Api
  module V1
    class StudyMaterialsController < ApplicationController
      before_action :require_user!
      before_action :require_study_feature!

      PER_LEVEL_PICK = 2
      AI_PICK        = 2
      # "Power of choices" candidate pool size — sample this many
      # random rows per level, then pick the PER_LEVEL_PICK with the
      # lowest view_count from that pool. Cheap (~4 rows scanned per
      # level instead of a full ORDER BY view_count) but still gives
      # the underused rows a fair shot at rotation.
      CANDIDATE_POOL = 4

      def index
        seeded = StudyMaterial::LEVELS.flat_map { |level| pick_underused(level: level, count: PER_LEVEL_PICK) }

        ai_generated = StudyMaterial
                         .where(ai_generated: true)
                         .order(Arel.sql("RANDOM()"))
                         .limit(AI_PICK)
                         .to_a

        all_picked = seeded + ai_generated
        if all_picked.any?
          StudyMaterial.where(id: all_picked.map(&:id))
                       .update_all("view_count = view_count + 1")
        end

        render json: {
          seeded:       seeded.map       { |m| serialize(m) },
          ai_generated: ai_generated.map { |m| serialize(m) }
        }
      end

      def show
        material = StudyMaterial.find(params[:id])
        render json: serialize(material)
      end

      # POST /api/v1/study_materials/generate
      # Body: { topic: "negotiating a salary" }
      #
      # Calls Gemini and caches the resulting row. Lives under the same
      # controller (instead of a separate generators controller) because
      # the result IS a study material — the route matches the resource.
      def generate
        topic = params.require(:topic).to_s.strip
        material = StudyMaterials::Generate.call(topic: topic, user: current_user)
        render status: :created, json: serialize(material)
      rescue StudyMaterials::Generate::GenerationLimitReached => e
        render status: :unprocessable_entity, json: {
          error: "generation_limit_reached",
          message: e.message,
          limit: StudyMaterials::Generate::MAX_PER_USER,
          used: current_user.study_generations_used
        }
      rescue StudyMaterials::Generate::InappropriateContent => e
        render status: :unprocessable_entity, json: {
          error: "inappropriate_content",
          message: e.message
        }
      rescue StudyMaterials::Generate::Error => e
        render status: :bad_gateway, json: { error: "generation_failed", message: e.message }
      rescue GeminiClient::Error => e
        render status: :bad_gateway, json: { error: "ai_failed", message: e.message }
      end

      private

      # Power-of-choices sampler: take CANDIDATE_POOL random rows of
      # the requested level (still seeded, not AI-generated), then
      # pick the `count` with the smallest view_count. Approximates a
      # least-frequently-used rotation without paying for a global
      # ORDER BY view_count over the whole table.
      def pick_underused(level:, count:, exclude_ids: [])
        scope = StudyMaterial.where(ai_generated: false, level: level)
        scope = scope.where.not(id: exclude_ids) if exclude_ids.any?

        candidates = scope.order(Arel.sql("RANDOM()")).limit(CANDIDATE_POOL).to_a
        candidates.sort_by { |m| [m.view_count, rand] }.first(count)
      end

      def require_study_feature!
        return if current_user.has_feature?("study")

        render status: :forbidden, json: { error: "membership_required", feature: "study" }
      end

      def serialize(material)
        {
          id: material.id,
          slug: material.slug,
          title: material.title,
          level: material.level,
          category: material.category,
          description: material.description,
          scenario_prompt: material.scenario_prompt,
          key_expressions: material.key_expressions,
          example_dialogue: material.example_dialogue,
          ai_generated: material.ai_generated
        }
      end
    end
  end
end

class AddStudyGenerationsUsedToUsers < ActiveRecord::Migration[7.2]
  def change
    # Lifetime counter for `StudyMaterials::Generate` calls per user.
    # We cap study learners at MAX_STUDY_GENERATIONS_PER_USER (= 3 at
    # the time of writing) so a single Basic-tier learner can't burn
    # the global Gemini budget — and because every successful generation
    # is cached in the shared study_materials pool, the OTHER users
    # benefit from the topics this user paid for. The cap is enforced
    # in `StudyMaterials::Generate.call(user:)`.
    add_column :users, :study_generations_used, :integer, null: false, default: 0
  end
end

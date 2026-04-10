class AddViewCountToStudyMaterials < ActiveRecord::Migration[7.2]
  def change
    # Lifetime view counter used by `StudyMaterialsController#index`'s
    # round-robin sampler. The index endpoint orders candidates by
    # view_count ASC then RANDOM(), so the *least*-shown rows in each
    # difficulty bucket get a fresh chance ahead of the popular ones —
    # learners eventually rotate through the entire seeded curriculum
    # instead of seeing the same 8 cards on every refresh. Picked rows
    # have their counter bumped at the end of the request.
    add_column :study_materials, :view_count, :integer, null: false, default: 0
    add_index  :study_materials, :view_count
  end
end

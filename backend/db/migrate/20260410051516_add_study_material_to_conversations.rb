class AddStudyMaterialToConversations < ActiveRecord::Migration[7.2]
  def change
    add_reference :conversations, :study_material, null: true, foreign_key: true
  end
end

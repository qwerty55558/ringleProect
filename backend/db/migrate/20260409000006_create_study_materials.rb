class CreateStudyMaterials < ActiveRecord::Migration[7.2]
  def change
    # Curriculum units the learner can pick before entering /conversation.
    # Each row caches one AI-generated (or hand-seeded) study scenario;
    # the cache means we never re-bill Gemini for the same topic and the
    # curriculum is deterministic across reloads.
    create_table :study_materials do |t|
      t.string  :slug,             null: false
      t.string  :title,            null: false
      t.string  :level,            null: false, default: "beginner"
      t.string  :category,         null: false, default: "daily" # daily | business | travel | ...
      t.text    :description,      null: false # Korean blurb shown in the list card
      t.text    :scenario_prompt,  null: false # Primes the AI tutor's system prompt
      t.json    :key_expressions,  null: false, default: []
      t.json    :example_dialogue, null: false, default: []
      t.boolean :ai_generated,     null: false, default: false
      t.timestamps
      t.index :slug, unique: true
      t.index :category
    end
  end
end

class CreateTtsArtifacts < ActiveRecord::Migration[7.2]
  def change
    # Per-(text, voice, model) cache of synthesised TTS clips. Lets us
    # serve the assistant's "Hi! I'm Ringle..." opener (and any other
    # repeated phrase) without re-billing ElevenLabs every time.
    create_table :tts_artifacts do |t|
      t.string :content_hash, null: false
      t.string :voice_id,     null: false
      t.string :model_id,     null: false
      t.timestamps
      t.index [:content_hash, :voice_id, :model_id],
              name: "index_tts_artifacts_lookup", unique: true
    end
  end
end

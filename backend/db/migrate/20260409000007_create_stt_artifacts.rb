class CreateSttArtifacts < ActiveRecord::Migration[7.2]
  def change
    # Per-(audio_bytes) cache of STT transcriptions. Two responsibilities:
    #   1. cost / latency: Gemini transcribes the same recording at most once
    #   2. demo fixtures: rows with a non-null `slug` are pre-seeded WAV
    #      examples the frontend can pick to drive the conversation flow
    #      without an actual microphone (useful when demoing from an office)
    create_table :stt_artifacts do |t|
      t.string :audio_hash, null: false
      t.text   :text,       null: false
      t.string :slug                       # nil for ad-hoc cache rows, set for fixtures
      t.string :label                      # human-readable label for the fixture picker
      t.string :mime_type, null: false, default: "audio/wav"
      t.integer :byte_size
      t.timestamps
      t.index :audio_hash, unique: true
      t.index :slug,       unique: true
    end
  end
end

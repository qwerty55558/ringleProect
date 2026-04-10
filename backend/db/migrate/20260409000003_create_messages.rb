class CreateMessages < ActiveRecord::Migration[7.2]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string  :role, null: false # user | assistant
      t.text    :text, null: false
      # SHA256 of the *text* — used to look up a TtsArtifact when we
      # synthesise the assistant's voice, so the same sentence is never
      # billed twice across the whole product.
      t.string  :content_hash
      # Position within the conversation. Increments per turn.
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [:conversation_id, :position]
      t.index :content_hash
    end
  end
end

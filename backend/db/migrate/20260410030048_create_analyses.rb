class CreateAnalyses < ActiveRecord::Migration[7.2]
  def change
    create_table :analyses do |t|
      t.references :conversation, null: false, foreign_key: true
      t.text :result
      t.datetime :analyzed_at, null: false

      t.timestamps
    end

    add_index :analyses, [:conversation_id, :created_at]
  end
end

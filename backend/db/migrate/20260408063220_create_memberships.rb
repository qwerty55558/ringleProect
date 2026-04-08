class CreateMemberships < ActiveRecord::Migration[7.2]
  def change
    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :membership_plan, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :expires_at, null: false
      t.string :status, null: false, default: "active"
      t.string :source, null: false

      t.timestamps
    end
    add_index :memberships, [:user_id, :status]
    add_index :memberships, :expires_at
  end
end

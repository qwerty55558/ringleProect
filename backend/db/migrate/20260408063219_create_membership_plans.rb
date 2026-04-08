class CreateMembershipPlans < ActiveRecord::Migration[7.2]
  def change
    create_table :membership_plans do |t|
      t.string :name, null: false
      t.integer :price_cents, null: false, default: 0
      t.integer :duration_days, null: false
      t.json :features, null: false, default: []
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end

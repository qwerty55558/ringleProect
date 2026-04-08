class CreatePayments < ActiveRecord::Migration[7.2]
  def change
    create_table :payments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :membership_plan, null: false, foreign_key: true
      t.references :membership, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :status, null: false
      t.string :pg_transaction_id

      t.timestamps
    end
    add_index :payments, :pg_transaction_id, unique: true
  end
end

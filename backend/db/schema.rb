# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_04_08_063221) do
  create_table "membership_plans", force: :cascade do |t|
    t.string "name", null: false
    t.integer "price_cents", default: 0, null: false
    t.integer "duration_days", null: false
    t.json "features", default: [], null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "memberships", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "membership_plan_id", null: false
    t.datetime "started_at", null: false
    t.datetime "expires_at", null: false
    t.string "status", default: "active", null: false
    t.string "source", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_memberships_on_expires_at"
    t.index ["membership_plan_id"], name: "index_memberships_on_membership_plan_id"
    t.index ["user_id", "status"], name: "index_memberships_on_user_id_and_status"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "payments", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "membership_plan_id", null: false
    t.integer "membership_id"
    t.integer "amount_cents", null: false
    t.string "status", null: false
    t.string "pg_transaction_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["membership_id"], name: "index_payments_on_membership_id"
    t.index ["membership_plan_id"], name: "index_payments_on_membership_plan_id"
    t.index ["pg_transaction_id"], name: "index_payments_on_pg_transaction_id", unique: true
    t.index ["user_id"], name: "index_payments_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.string "role", default: "user", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "memberships", "membership_plans"
  add_foreign_key "memberships", "users"
  add_foreign_key "payments", "membership_plans"
  add_foreign_key "payments", "memberships"
  add_foreign_key "payments", "users"
end

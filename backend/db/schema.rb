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

ActiveRecord::Schema[7.2].define(version: 2026_04_10_051516) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.integer "record_id", null: false
    t.integer "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "analyses", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.text "result"
    t.datetime "analyzed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "pending", null: false
    t.index ["conversation_id", "created_at"], name: "index_analyses_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_analyses_on_conversation_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "title"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "context_summary"
    t.integer "study_material_id"
    t.index ["study_material_id"], name: "index_conversations_on_study_material_id"
    t.index ["user_id", "created_at"], name: "index_conversations_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_conversations_on_user_id"
  end

  create_table "membership_plans", force: :cascade do |t|
    t.string "name", null: false
    t.integer "price_cents", default: 0, null: false
    t.integer "duration_days", null: false
    t.json "features", default: [], null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "duration_seconds"
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

  create_table "messages", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.string "role", null: false
    t.text "text", null: false
    t.string "content_hash"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["content_hash"], name: "index_messages_on_content_hash"
    t.index ["conversation_id", "position"], name: "index_messages_on_conversation_id_and_position"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
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

  create_table "stt_artifacts", force: :cascade do |t|
    t.string "audio_hash", null: false
    t.text "text", null: false
    t.string "slug"
    t.string "label"
    t.string "mime_type", default: "audio/wav", null: false
    t.integer "byte_size"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["audio_hash"], name: "index_stt_artifacts_on_audio_hash", unique: true
    t.index ["slug"], name: "index_stt_artifacts_on_slug", unique: true
  end

  create_table "study_materials", force: :cascade do |t|
    t.string "slug", null: false
    t.string "title", null: false
    t.string "level", default: "beginner", null: false
    t.string "category", default: "daily", null: false
    t.text "description", null: false
    t.text "scenario_prompt", null: false
    t.json "key_expressions", default: [], null: false
    t.json "example_dialogue", default: [], null: false
    t.boolean "ai_generated", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "view_count", default: 0, null: false
    t.index ["category"], name: "index_study_materials_on_category"
    t.index ["slug"], name: "index_study_materials_on_slug", unique: true
    t.index ["view_count"], name: "index_study_materials_on_view_count"
  end

  create_table "tts_artifacts", force: :cascade do |t|
    t.string "content_hash", null: false
    t.string "voice_id", null: false
    t.string "model_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["content_hash", "voice_id", "model_id"], name: "index_tts_artifacts_lookup", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.string "role", default: "user", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "study_generations_used", default: 0, null: false
    t.integer "study_profanity_offenses", default: 0, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "analyses", "conversations"
  add_foreign_key "conversations", "study_materials"
  add_foreign_key "conversations", "users"
  add_foreign_key "memberships", "membership_plans"
  add_foreign_key "memberships", "users"
  add_foreign_key "messages", "conversations"
  add_foreign_key "payments", "membership_plans"
  add_foreign_key "payments", "memberships"
  add_foreign_key "payments", "users"
end

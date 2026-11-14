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

ActiveRecord::Schema[8.1].define(version: 2026_11_14_000003) do
  create_table "backup_runs", force: :cascade do |t|
    t.string "status", default: "running", null: false
    t.datetime "started_at", null: false
    t.datetime "completed_at"
    t.string "destination", null: false
    t.bigint "byte_size"
    t.string "sha256"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["started_at"], name: "index_backup_runs_on_started_at"
  end

  create_table "day_notes", force: :cascade do |t|
    t.string "uuid", null: false
    t.integer "user_id", null: false
    t.date "local_date", null: false
    t.text "notes"
    t.json "metrics", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "local_date"], name: "index_day_notes_on_user_id_and_local_date", unique: true
    t.index ["user_id", "uuid"], name: "index_day_notes_on_user_id_and_uuid", unique: true
    t.index ["user_id"], name: "index_day_notes_on_user_id"
  end

  create_table "import_batches", id: :string, force: :cascade do |t|
    t.integer "user_id", null: false
    t.json "payload", null: false
    t.datetime "committed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_import_batches_on_user_id"
  end

  create_table "injections", force: :cascade do |t|
    t.string "uuid", null: false
    t.integer "user_id", null: false
    t.string "occurred_at", null: false
    t.datetime "recorded_at", null: false
    t.decimal "dose", precision: 5, scale: 2, null: false
    t.string "site"
    t.string "side"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "recorded_at"], name: "index_injections_on_user_id_and_recorded_at"
    t.index ["user_id", "uuid"], name: "index_injections_on_user_id_and_uuid", unique: true
    t.index ["user_id"], name: "index_injections_on_user_id"
  end

  create_table "login_attempts", force: :cascade do |t|
    t.string "key", null: false
    t.integer "count", default: 0, null: false
    t.datetime "window_started_at", null: false
    t.index ["key"], name: "index_login_attempts_on_key", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "token", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "preferred_unit", default: "lb", null: false
    t.string "time_zone", default: "America/New_York", null: false
    t.json "enabled_metrics", default: [], null: false
    t.datetime "reminder_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "weight_goal"
    t.decimal "height_cm", precision: 8, scale: 4
    t.json "chart_preferences", default: {}, null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "weights", force: :cascade do |t|
    t.string "uuid", null: false
    t.integer "user_id", null: false
    t.string "occurred_at", null: false
    t.datetime "recorded_at", null: false
    t.decimal "value", precision: 10, scale: 4, null: false
    t.string "unit", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "recorded_at"], name: "index_weights_on_user_id_and_recorded_at"
    t.index ["user_id", "uuid"], name: "index_weights_on_user_id_and_uuid", unique: true
    t.index ["user_id"], name: "index_weights_on_user_id"
  end

  add_foreign_key "day_notes", "users"
  add_foreign_key "import_batches", "users"
  add_foreign_key "injections", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "weights", "users"
end

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

ActiveRecord::Schema[8.1].define(version: 2026_10_19_164146) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "churches", force: :cascade do |t|
    t.string "name", null: false
    t.string "ccli_license_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "live_sessions", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.bigint "service_set_id", null: false
    t.string "status", default: "active", null: false
    t.bigint "current_set_item_id"
    t.integer "current_section_index", default: 0, null: false
    t.bigint "position_version", default: 0, null: false
    t.integer "lock_version", default: 0, null: false
    t.boolean "blanked", default: false, null: false
    t.integer "font_scale", default: 100, null: false
    t.string "projector_token"
    t.string "musician_token"
    t.datetime "started_at"
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id"], name: "index_live_sessions_on_church_id"
    t.index ["current_set_item_id"], name: "index_live_sessions_on_current_set_item_id"
    t.index ["musician_token"], name: "index_live_sessions_on_musician_token", unique: true
    t.index ["projector_token"], name: "index_live_sessions_on_projector_token", unique: true
    t.index ["service_set_id"], name: "index_live_sessions_on_service_set_id"
    t.check_constraint "current_section_index >= 0", name: "live_sessions_section_index_check"
    t.check_constraint "font_scale >= 50 AND font_scale <= 400", name: "live_sessions_font_scale_check"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'ended'::character varying]::text[])", name: "live_sessions_status_check"
  end

  create_table "service_sets", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.string "name", null: false
    t.date "service_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id", "service_date"], name: "index_service_sets_on_church_id_and_service_date"
  end

  create_table "set_items", force: :cascade do |t|
    t.bigint "service_set_id", null: false
    t.integer "position", null: false
    t.string "item_type", null: false
    t.bigint "song_id"
    t.bigint "text_slide_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["service_set_id", "position"], name: "index_set_items_on_service_set_id_and_position", unique: true
    t.index ["service_set_id"], name: "index_set_items_on_service_set_id"
    t.index ["song_id"], name: "index_set_items_on_song_id"
    t.index ["text_slide_id"], name: "index_set_items_on_text_slide_id"
    t.check_constraint "((song_id IS NOT NULL)::integer + (text_slide_id IS NOT NULL)::integer) = 1", name: "set_items_exactly_one_item_check"
    t.check_constraint "\"position\" >= 0", name: "set_items_position_check"
    t.check_constraint "item_type::text = ANY (ARRAY['song'::character varying, 'text_slide'::character varying]::text[])", name: "set_items_item_type_check"
  end

  create_table "songs", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.string "title", null: false
    t.string "author"
    t.string "subtitle"
    t.string "reference"
    t.string "link"
    t.string "song_key"
    t.integer "capo", default: 0, null: false
    t.string "copyright_line"
    t.integer "ccli_song_number"
    t.string "copyright_status", default: "unknown", null: false
    t.text "chordpro_source"
    t.jsonb "parsed_lyric"
    t.text "plain_text"
    t.jsonb "arrangement"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id", "title"], name: "index_songs_on_church_id_and_title"
    t.index ["plain_text"], name: "index_songs_on_plain_text_trgm", opclass: :gin_trgm_ops, using: :gin
    t.check_constraint "capo >= 0 AND capo <= 11", name: "songs_capo_check"
    t.check_constraint "copyright_status::text = ANY (ARRAY['copyrighted'::character varying, 'public_domain'::character varying, 'unknown'::character varying]::text[])", name: "songs_copyright_status_check"
  end

  create_table "text_slides", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.string "title", null: false
    t.string "subtype", default: "statement", null: false
    t.text "body_markdown"
    t.boolean "reusable", default: true, null: false
    t.bigint "set_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id", "title"], name: "index_text_slides_on_church_id_and_title"
    t.index ["set_id"], name: "index_text_slides_on_set_id"
    t.check_constraint "subtype::text = ANY (ARRAY['statement'::character varying, 'blessing'::character varying, 'statement_of_faith'::character varying, 'question'::character varying, 'sermon_point'::character varying, 'scripture'::character varying, 'announcement'::character varying]::text[])", name: "text_slides_subtype_check"
  end

  create_table "users", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.citext "email", null: false
    t.string "password_digest", null: false
    t.string "role", default: "editor", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id", "email"], name: "index_users_on_church_id_and_email", unique: true
    t.check_constraint "role::text = ANY (ARRAY['admin'::character varying, 'editor'::character varying]::text[])", name: "users_role_check"
  end

  add_foreign_key "live_sessions", "churches"
  add_foreign_key "live_sessions", "service_sets"
  add_foreign_key "live_sessions", "set_items", column: "current_set_item_id"
  add_foreign_key "service_sets", "churches"
  add_foreign_key "set_items", "service_sets"
  add_foreign_key "set_items", "songs"
  add_foreign_key "set_items", "text_slides"
  add_foreign_key "songs", "churches"
  add_foreign_key "text_slides", "churches"
  add_foreign_key "text_slides", "service_sets", column: "set_id", on_delete: :cascade
  add_foreign_key "users", "churches"
end

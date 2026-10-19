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

ActiveRecord::Schema[8.1].define(version: 2026_10_19_151627) do
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

  add_foreign_key "songs", "churches"
  add_foreign_key "users", "churches"
end

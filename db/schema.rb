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

ActiveRecord::Schema[8.1].define(version: 2026_10_22_203500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
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
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "churches", force: :cascade do |t|
    t.string "name", null: false
    t.string "ccli_license_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.citext "subdomain"
    t.string "projector_bg_color", default: "#000000", null: false
    t.string "projector_text_color", default: "#ffffff", null: false
    t.string "projector_lyric_case", default: "none", null: false
    t.string "projector_title_case", default: "none", null: false
    t.string "projector_font", default: "sans", null: false
    t.string "projector_line_height", default: "normal", null: false
    t.boolean "projector_bold", default: true, null: false
    t.boolean "projector_show_credits", default: true, null: false
    t.string "projector_valign", default: "center", null: false
    t.string "projector_pagination", default: "by_section", null: false
    t.integer "projector_lines_per_slide", default: 4, null: false
    t.string "projector_bg_type", default: "solid", null: false
    t.string "projector_bg_color2", default: "#1a1a2e", null: false
    t.integer "projector_bg_gradient_angle", default: 160, null: false
    t.index ["subdomain"], name: "index_churches_on_subdomain", unique: true, where: "(subdomain IS NOT NULL)"
    t.check_constraint "projector_bg_gradient_angle >= 0 AND projector_bg_gradient_angle <= 360", name: "churches_projector_bg_gradient_angle_check"
    t.check_constraint "projector_lines_per_slide >= 1 AND projector_lines_per_slide <= 20", name: "churches_projector_lines_per_slide_check"
  end

  create_table "invitations", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.bigint "invited_by_id", null: false
    t.citext "email", null: false
    t.string "role", default: "editor", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["church_id", "email"], name: "index_pending_invitations", unique: true, where: "(accepted_at IS NULL)"
    t.index ["church_id"], name: "index_invitations_on_church_id"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
    t.check_constraint "role::text = ANY (ARRAY['admin'::text, 'editor'::text])", name: "invitations_role_check"
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
    t.integer "current_chunk_index", default: 0, null: false
    t.index ["church_id"], name: "index_live_sessions_on_church_id"
    t.index ["church_id"], name: "index_one_active_live_session_per_church", unique: true, where: "((status)::text = 'active'::text)"
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
    t.text "body_markdown"
    t.boolean "reusable", default: true, null: false
    t.bigint "set_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "tags", default: [], null: false
    t.jsonb "pages", default: [], null: false
    t.integer "font_size"
    t.index ["church_id", "title"], name: "index_text_slides_on_church_id_and_title"
    t.index ["set_id"], name: "index_text_slides_on_set_id"
    t.index ["tags"], name: "index_text_slides_on_tags", using: :gin
    t.check_constraint "font_size IS NULL OR font_size >= 2 AND font_size <= 30", name: "text_slides_font_size_check"
  end

  create_table "usage_events", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.bigint "live_session_id", null: false
    t.bigint "song_id", null: false
    t.integer "ccli_song_number"
    t.string "title"
    t.string "author"
    t.string "copyright_status"
    t.datetime "shown_at", null: false
    t.datetime "created_at", null: false
    t.index ["church_id", "shown_at"], name: "index_usage_events_on_church_id_and_shown_at"
    t.index ["live_session_id", "song_id"], name: "index_usage_events_on_live_session_id_and_song_id", unique: true
    t.index ["song_id"], name: "index_usage_events_on_song_id"
  end

  create_table "users", force: :cascade do |t|
    t.bigint "church_id", null: false
    t.citext "email", null: false
    t.string "password_digest", null: false
    t.string "role", default: "editor", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "confirmed_at"
    t.string "confirmation_token_digest"
    t.datetime "confirmation_sent_at"
    t.index ["church_id", "email"], name: "index_users_on_church_id_and_email", unique: true
    t.index ["confirmation_token_digest"], name: "index_users_on_confirmation_token_digest", unique: true, where: "(confirmation_token_digest IS NOT NULL)"
    t.check_constraint "role::text = ANY (ARRAY['admin'::character varying, 'editor'::character varying]::text[])", name: "users_role_check"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "invitations", "churches"
  add_foreign_key "invitations", "users", column: "invited_by_id"
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
  add_foreign_key "usage_events", "churches"
  add_foreign_key "usage_events", "live_sessions"
  add_foreign_key "usage_events", "songs"
  add_foreign_key "users", "churches"
end

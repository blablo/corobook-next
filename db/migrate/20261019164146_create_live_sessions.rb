class CreateLiveSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :live_sessions do |t|
      t.references :church, null: false, foreign_key: true
      t.references :service_set, null: false, foreign_key: true
      t.string :status, null: false, default: "active"
      t.references :current_set_item, null: true, foreign_key: { to_table: :set_items }
      t.integer :current_section_index, null: false, default: 0
      t.bigint :position_version, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.boolean :blanked, null: false, default: false
      t.integer :font_scale, null: false, default: 100
      t.string :projector_token
      t.string :musician_token
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end

    add_index :live_sessions, :projector_token, unique: true
    add_index :live_sessions, :musician_token, unique: true
    add_check_constraint :live_sessions, "status IN ('active', 'ended')", name: "live_sessions_status_check"
    add_check_constraint :live_sessions, "current_section_index >= 0", name: "live_sessions_section_index_check"
    add_check_constraint :live_sessions, "font_scale >= 50 AND font_scale <= 400", name: "live_sessions_font_scale_check"
  end
end

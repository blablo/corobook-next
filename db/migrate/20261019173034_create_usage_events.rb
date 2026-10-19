class CreateUsageEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_events do |t|
      t.references :church, null: false, foreign_key: true, index: false
      t.references :live_session, null: false, foreign_key: true, index: false
      t.references :song, null: false, foreign_key: true
      t.integer :ccli_song_number
      t.string :title
      t.string :author
      t.string :copyright_status
      t.datetime :shown_at, null: false

      t.datetime :created_at, null: false
    end

    # One use per song per session (idempotent capture, §7).
    add_index :usage_events, [ :live_session_id, :song_id ], unique: true
    add_index :usage_events, [ :church_id, :shown_at ]
  end
end

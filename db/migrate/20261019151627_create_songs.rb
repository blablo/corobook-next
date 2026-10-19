class CreateSongs < ActiveRecord::Migration[8.1]
  def change
    create_table :songs do |t|
      t.references :church, null: false, foreign_key: true, index: false
      t.string :title, null: false
      t.string :author
      t.string :subtitle
      t.string :reference
      t.string :link
      t.string :song_key
      t.integer :capo, null: false, default: 0
      t.string :copyright_line
      t.integer :ccli_song_number
      t.string :copyright_status, null: false, default: "unknown"
      t.text :chordpro_source
      t.jsonb :parsed_lyric
      t.text :plain_text
      t.jsonb :arrangement

      t.timestamps
    end

    add_index :songs, [ :church_id, :title ]
    add_index :songs, :plain_text, using: :gin, opclass: :gin_trgm_ops, name: "index_songs_on_plain_text_trgm"
    add_check_constraint :songs, "capo >= 0 AND capo <= 11", name: "songs_capo_check"
    add_check_constraint :songs,
      "copyright_status IN ('copyrighted', 'public_domain', 'unknown')",
      name: "songs_copyright_status_check"
  end
end

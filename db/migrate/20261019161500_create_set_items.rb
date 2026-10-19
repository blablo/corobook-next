class CreateSetItems < ActiveRecord::Migration[8.1]
  def change
    create_table :set_items do |t|
      t.references :service_set, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :item_type, null: false
      t.references :song, null: true, foreign_key: true
      t.references :text_slide, null: true, foreign_key: true

      t.timestamps
    end

    add_index :set_items, [ :service_set_id, :position ], unique: true
    add_check_constraint :set_items, "position >= 0", name: "set_items_position_check"
    add_check_constraint :set_items, "item_type IN ('song', 'text_slide')", name: "set_items_item_type_check"
    # Exactly one of the two item FKs is set — a DB-enforced discriminated union (design §2.2).
    add_check_constraint :set_items,
      "(song_id IS NOT NULL)::int + (text_slide_id IS NOT NULL)::int = 1",
      name: "set_items_exactly_one_item_check"
  end
end

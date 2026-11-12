# Service templates: a template is a ServiceSet flagged `template`, built in the same set builder.
# Its items are fixed songs/slides or SLOTS: a labelled placeholder (song slot, or a slide slot tied
# to a slide tag) that each service created from the template fills in.
class AddServiceTemplates < ActiveRecord::Migration[8.1]
  OLD_ITEM_CHECK = "((song_id IS NOT NULL)::integer + (text_slide_id IS NOT NULL)::integer) = 1"
  # A regular item references exactly one song or slide; a slot (slot_label set) references at
  # most one, so it may be empty until filled.
  NEW_ITEM_CHECK = "((song_id IS NOT NULL)::integer + (text_slide_id IS NOT NULL)::integer) = 1 " \
                   "OR (slot_label IS NOT NULL AND song_id IS NULL AND text_slide_id IS NULL)"

  def change
    add_column :service_sets, :template, :boolean, default: false, null: false
    add_index :service_sets, [ :church_id, :template ]

    add_reference :churches, :default_template, null: true,
                  foreign_key: { to_table: :service_sets, on_delete: :nullify }

    add_column :set_items, :slot_label, :string
    add_column :set_items, :slot_tag, :string

    remove_check_constraint :set_items, OLD_ITEM_CHECK, name: "set_items_exactly_one_item_check"
    add_check_constraint :set_items, NEW_ITEM_CHECK, name: "set_items_item_or_slot_check"
  end
end

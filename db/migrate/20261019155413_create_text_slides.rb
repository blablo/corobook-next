class CreateTextSlides < ActiveRecord::Migration[8.1]
  SUBTYPES = %w[statement blessing statement_of_faith question sermon_point scripture announcement].freeze

  def change
    create_table :text_slides do |t|
      t.references :church, null: false, foreign_key: true, index: false
      t.string :title, null: false
      t.string :subtype, null: false, default: "statement"
      t.text :body_markdown
      t.boolean :reusable, null: false, default: true
      # Only set for inline one-off slides; the FK to `sets` is added in Phase 6 when that table
      # exists. Reusable slide: reusable=true, set_id=null. Inline slide: reusable=false, set_id set.
      t.bigint :set_id, null: true

      t.timestamps
    end

    add_index :text_slides, [ :church_id, :title ]
    add_index :text_slides, :set_id
    add_check_constraint :text_slides,
      "subtype IN (#{SUBTYPES.map { |s| "'#{s}'" }.join(', ')})",
      name: "text_slides_subtype_check"
  end
end

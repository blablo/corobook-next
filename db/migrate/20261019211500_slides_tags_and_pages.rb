class SlidesTagsAndPages < ActiveRecord::Migration[8.0]
  def up
    add_column :text_slides, :tags, :jsonb, null: false, default: []
    add_column :text_slides, :pages, :jsonb, null: false, default: []

    # Backfill losslessly: subtype -> a tag; body_markdown -> the single first page.
    execute <<~SQL.squish
      UPDATE text_slides
         SET tags  = to_jsonb(ARRAY[subtype]),
             pages = jsonb_build_array(
                       jsonb_build_object('body_markdown', COALESCE(body_markdown, ''))
                     )
    SQL

    remove_column :text_slides, :subtype # drops the column and its check constraint
    add_index :text_slides, :tags, using: :gin
  end

  def down
    remove_index :text_slides, :tags
    add_column :text_slides, :subtype, :string, null: false, default: "statement"
    add_check_constraint :text_slides,
      "subtype::text = ANY (ARRAY['statement','blessing','statement_of_faith','question','sermon_point','scripture','announcement']::text[])",
      name: "text_slides_subtype_check"
    # Restore body_markdown from the first page where it was emptied.
    execute <<~SQL.squish
      UPDATE text_slides
         SET body_markdown = COALESCE(pages->0->>'body_markdown', body_markdown)
    SQL
    remove_column :text_slides, :tags
    remove_column :text_slides, :pages
  end
end

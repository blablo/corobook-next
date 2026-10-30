class AddArchivedAtToTextSlides < ActiveRecord::Migration[8.1]
  # Archived library slides are hidden from the library, search and the set builder, and listed
  # only on the Archived slides page. Nil = active.
  def change
    add_column :text_slides, :archived_at, :datetime
    add_index :text_slides, [ :church_id, :archived_at ]
  end
end

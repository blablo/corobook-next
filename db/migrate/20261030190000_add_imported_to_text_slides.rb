class AddImportedToTextSlides < ActiveRecord::Migration[8.1]
  # A slide imported from a PDF (e.g. a Google Slides / PowerPoint / Keynote export): each page is
  # a rendered image (TextSlide#page_images) instead of editable text.
  def change
    add_column :text_slides, :imported, :boolean, default: false, null: false
  end
end

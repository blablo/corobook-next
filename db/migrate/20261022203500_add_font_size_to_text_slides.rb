class AddFontSizeToTextSlides < ActiveRecord::Migration[8.1]
  def change
    # Fixed projection font size for every page of the slide, as a percentage of the screen
    # (container) height. NULL = auto: the text is scaled to fit the screen.
    add_column :text_slides, :font_size, :integer
    add_check_constraint :text_slides, "font_size IS NULL OR (font_size >= 2 AND font_size <= 30)",
      name: "text_slides_font_size_check"
  end
end

class AddProjectorMinFontSizeToChurches < ActiveRecord::Migration[8.1]
  def change
    # Smallest song lyric size (% of screen height) before a section is split onto more slides.
    add_column :churches, :projector_min_font_size, :integer
    add_check_constraint :churches,
      "projector_min_font_size IS NULL OR (projector_min_font_size >= 2 AND projector_min_font_size <= 30)",
      name: "churches_projector_min_font_size_check"
  end
end

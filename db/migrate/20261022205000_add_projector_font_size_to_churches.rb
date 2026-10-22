class AddProjectorFontSizeToChurches < ActiveRecord::Migration[8.1]
  def change
    # Fixed font size for song lyric slides, as a percentage of the screen (container) height.
    # NULL = auto: the lyrics are scaled to fit the screen.
    add_column :churches, :projector_font_size, :integer
    add_check_constraint :churches,
      "projector_font_size IS NULL OR (projector_font_size >= 2 AND projector_font_size <= 30)",
      name: "churches_projector_font_size_check"
  end
end

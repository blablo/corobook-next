class AddAlignmentToTextSlides < ActiveRecord::Migration[8.1]
  # Per-slide text placement on the projector: horizontal (left/center/right) and vertical
  # (top/center/bottom). Defaults keep every existing slide centered, as before.
  def change
    add_column :text_slides, :text_align, :string, default: "center", null: false
    add_column :text_slides, :vertical_align, :string, default: "center", null: false
    add_check_constraint :text_slides, "text_align IN ('left', 'center', 'right')",
                         name: "text_slides_text_align_check"
    add_check_constraint :text_slides, "vertical_align IN ('top', 'center', 'bottom')",
                         name: "text_slides_vertical_align_check"
  end
end

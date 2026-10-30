class AddLookToTextSlides < ActiveRecord::Migration[8.1]
  # Per-slide projection look, the same options as Song projection: background type (solid,
  # gradient or image), two colours + angle for the gradient, text colour and font. The defaults
  # reproduce how slides looked before (black background, white sans-serif text).
  def up
    change_table :text_slides, bulk: true do |t|
      t.string  :bg_type, default: "solid", null: false
      t.string  :bg_color, default: "#000000", null: false
      t.string  :bg_color2, default: "#1a1a2e", null: false
      t.integer :bg_gradient_angle, default: 160, null: false
      t.string  :text_color, default: "#ffffff", null: false
      t.string  :font, default: "sans", null: false
    end
    add_check_constraint :text_slides, "bg_type IN ('solid', 'gradient', 'image')", name: "text_slides_bg_type_check"
    add_check_constraint :text_slides, "bg_gradient_angle >= 0 AND bg_gradient_angle <= 360",
                         name: "text_slides_bg_gradient_angle_check"

    # Slides that already have a background image keep showing it.
    execute <<~SQL
      UPDATE text_slides SET bg_type = 'image'
      WHERE id IN (SELECT record_id FROM active_storage_attachments
                   WHERE record_type = 'TextSlide' AND name = 'background_image')
    SQL
  end

  def down
    remove_check_constraint :text_slides, name: "text_slides_bg_gradient_angle_check"
    remove_check_constraint :text_slides, name: "text_slides_bg_type_check"
    change_table :text_slides, bulk: true do |t|
      t.remove :bg_type, :bg_color, :bg_color2, :bg_gradient_angle, :text_color, :font
    end
  end
end

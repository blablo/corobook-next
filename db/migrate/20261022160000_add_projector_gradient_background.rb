class AddProjectorGradientBackground < ActiveRecord::Migration[8.1]
  def change
    change_table :churches, bulk: true do |t|
      # Background type: "solid" (default, uses projector_bg_color) or "gradient" (a linear
      # gradient from projector_bg_color to projector_bg_color2 at the given angle).
      t.string  :projector_bg_type,          null: false, default: "solid" # solid | gradient
      t.string  :projector_bg_color2,        null: false, default: "#1a1a2e"
      t.integer :projector_bg_gradient_angle, null: false, default: 160
    end

    add_check_constraint :churches,
      "projector_bg_gradient_angle >= 0 AND projector_bg_gradient_angle <= 360",
      name: "churches_projector_bg_gradient_angle_check"
  end
end

# Line spacing becomes a PowerPoint-style multiple (1.0 / 1.15 / 1.5 / 2.0) instead of
# tight/normal/relaxed, and text slides get their own optional spacing (nil = as before).
class LineSpacingMultiples < ActiveRecord::Migration[8.1]
  MAP = { "tight" => "1.0", "normal" => "1.15", "relaxed" => "1.5" }.freeze

  def up
    MAP.each do |old, new|
      execute "UPDATE churches SET projector_line_height = '#{new}' WHERE projector_line_height = '#{old}'"
    end
    change_column_default :churches, :projector_line_height, from: "normal", to: "1.15"

    add_column :text_slides, :line_height, :string
    add_check_constraint :text_slides, "line_height IS NULL OR line_height IN ('1.0', '1.15', '1.5', '2.0')",
      name: "text_slides_line_height_check"
  end

  def down
    remove_check_constraint :text_slides, name: "text_slides_line_height_check"
    remove_column :text_slides, :line_height

    change_column_default :churches, :projector_line_height, from: "1.15", to: "normal"
    execute "UPDATE churches SET projector_line_height = 'normal' WHERE projector_line_height NOT IN ('1.0', '1.5')"
    MAP.each do |old, new|
      execute "UPDATE churches SET projector_line_height = '#{old}' WHERE projector_line_height = '#{new}'"
    end
  end
end

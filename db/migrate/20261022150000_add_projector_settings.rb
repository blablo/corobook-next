class AddProjectorSettings < ActiveRecord::Migration[8.1]
  def change
    # Per-church projection look & behaviour. Defaults reproduce today's exact "Classic" look
    # (true black / white, centered, section-paginated) so existing churches are unchanged.
    change_table :churches, bulk: true do |t|
      t.string  :projector_bg_color,     null: false, default: "#000000"
      t.string  :projector_text_color,   null: false, default: "#ffffff"
      t.string  :projector_lyric_case,   null: false, default: "none"   # none | upper | title
      t.string  :projector_title_case,   null: false, default: "none"   # none | upper | title
      t.string  :projector_font,         null: false, default: "sans"   # sans | serif | condensed | mono
      t.string  :projector_line_height,  null: false, default: "normal" # tight | normal | relaxed
      t.boolean :projector_bold,         null: false, default: true
      t.boolean :projector_show_credits, null: false, default: true
      t.string  :projector_valign,       null: false, default: "center" # top | center | bottom
      t.string  :projector_pagination,   null: false, default: "by_section" # by_section | by_lines
      t.integer :projector_lines_per_slide, null: false, default: 4
    end

    add_check_constraint :churches,
      "projector_lines_per_slide >= 1 AND projector_lines_per_slide <= 20",
      name: "churches_projector_lines_per_slide_check"

    # by_lines pagination needs a sub-position within a section. Nullable/0 in by_section mode,
    # so the existing section_index addressing is unchanged.
    add_column :live_sessions, :current_chunk_index, :integer, null: false, default: 0
  end
end

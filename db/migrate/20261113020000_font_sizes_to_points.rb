# Projector font sizes move from "% of screen height" to pt on a PowerPoint-sized screen, 540 pt
# tall (Corobook::FontSize). A stored % becomes the nearest offered pt size (5% = 27 pt -> 28 pt),
# so every saved value is one the size selects can show. The sizes change by at most a few %.
class FontSizesToPoints < ActiveRecord::Migration[8.1]
  SCREEN_HEIGHT_PT = 540
  OPTIONS = [ 20, 24, 28, 32, 36, 40, 44, 48, 54, 60, 66, 72, 80, 88, 96, 108, 120, 132 ].freeze

  COLUMNS = {
    text_slides: [ [ :font_size, "text_slides_font_size_check" ] ],
    churches: [
      [ :projector_font_size, "churches_projector_font_size_check" ],
      [ :projector_min_font_size, "churches_projector_min_font_size_check" ]
    ]
  }.freeze

  def up
    each_column do |table, column, check|
      remove_check_constraint table, name: check
      # One UPDATE with a CASE, so a converted value is never converted a second time.
      cases = (2..30).map { |pct| "WHEN #{pct} THEN #{nearest_option(pct)}" }.join(" ")
      execute "UPDATE #{table} SET #{column} = CASE #{column} #{cases} END WHERE #{column} IS NOT NULL"
      add_check_constraint table, "#{column} IS NULL OR (#{column} >= 10 AND #{column} <= 200)", name: check
    end
  end

  def down
    each_column do |table, column, check|
      remove_check_constraint table, name: check
      execute <<~SQL
        UPDATE #{table}
        SET #{column} = LEAST(30, GREATEST(2, ROUND(#{column} * 100.0 / #{SCREEN_HEIGHT_PT})))
        WHERE #{column} IS NOT NULL
      SQL
      add_check_constraint table, "#{column} IS NULL OR (#{column} >= 2 AND #{column} <= 30)", name: check
    end
  end

  private

  def each_column
    COLUMNS.each { |table, columns| columns.each { |column, check| yield table, column, check } }
  end

  def nearest_option(pct)
    OPTIONS.min_by { |pt| (pt - pct * SCREEN_HEIGHT_PT / 100.0).abs }
  end
end

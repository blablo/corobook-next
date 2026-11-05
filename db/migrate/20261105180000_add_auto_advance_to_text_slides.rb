class AddAutoAdvanceToTextSlides < ActiveRecord::Migration[8.1]
  def change
    # Auto-advance pages: nil seconds = off (each page is its own operator step).
    add_column :text_slides, :auto_advance_seconds, :integer
    add_column :text_slides, :auto_advance_loop, :boolean, default: true, null: false
    add_column :text_slides, :auto_advance_transition, :string, default: "fade", null: false
    add_check_constraint :text_slides, "auto_advance_seconds IS NULL OR auto_advance_seconds BETWEEN 2 AND 600",
                         name: "text_slides_auto_advance_seconds_range"

    # When the live position last moved: the shared clock every screen uses to work out which
    # page of an auto-advancing slide is showing, so they all stay in step.
    add_column :live_sessions, :position_changed_at, :datetime
  end
end

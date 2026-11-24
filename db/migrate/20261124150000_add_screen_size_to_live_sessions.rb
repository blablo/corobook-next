# The projector's screen size (CSS px), reported by the projector page, so the speaker view can
# lay the slide out at exactly that size and the speaker's drawing lands where it does on screen.
class AddScreenSizeToLiveSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :live_sessions, :screen_width, :integer
    add_column :live_sessions, :screen_height, :integer
  end
end

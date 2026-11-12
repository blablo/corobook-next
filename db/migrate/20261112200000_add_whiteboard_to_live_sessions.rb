# Speaker view and whiteboard. The pastor's tablet opens /s/:speaker_token (revoked when the
# service ends, like the projector and band links) and can cover the projector with a whiteboard
# or draw over the current slide. Strokes live on the session row so a projector reload, or a
# whiteboard reopened later in the sermon, comes back with the drawing.
class AddWhiteboardToLiveSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :live_sessions, :speaker_token, :string
    add_index :live_sessions, :speaker_token, unique: true

    # nil = off, "board" = whiteboard over the projector, "slide" = drawing on the current slide.
    add_column :live_sessions, :whiteboard_mode, :string
    add_check_constraint :live_sessions, "whiteboard_mode IS NULL OR whiteboard_mode IN ('board', 'slide')",
                         name: "live_sessions_whiteboard_mode_check"
    add_column :live_sessions, :whiteboard_dark, :boolean, default: false, null: false
    # Strokes: [{ "t" => tool, "c" => colour, "p" => [[x, y], ...] }], x/y as 0..1 of the screen.
    add_column :live_sessions, :whiteboard_board, :jsonb, default: [], null: false
    add_column :live_sessions, :whiteboard_slide, :jsonb, default: [], null: false
    # The stop the slide strokes were drawn on; they are dropped once the service moves off it.
    add_column :live_sessions, :whiteboard_slide_stop, :string

    # A service live during the deploy gets its speaker link now, not on the operator's first GET.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE live_sessions SET speaker_token = replace(gen_random_uuid()::text, '-', '')
          WHERE status = 'active' AND speaker_token IS NULL
        SQL
      end
    end
  end
end

# frozen_string_literal: true

module Corobook
  # The speaker's whiteboard for one live session. The speaker view (the pastor's tablet) puts a
  # whiteboard over the projector ("board") or draws over the current slide ("slide"); the
  # projector and the operator show the same strokes. Turning it on or off doesn't move the
  # position, so stopping shows whatever slide the service is on.
  #
  # Strokes are stored on the session row (board strokes stay until cleared; slide strokes belong
  # to one stop and are dropped once the service moves on) and travel over WhiteboardChannel.
  # Points are 0..1 of the screen so a tablet and a projector of any size agree.
  #
  # Writes lock the row and use update_columns, so they never bump lock_version and can't make an
  # operator's Next fail with a stale-object error.
  class Whiteboard
    MODES = %w[board slide].freeze
    TOOLS = %w[pen hl erase].freeze
    COLORS = %w[#111827 #f8fafc #2563eb #dc2626 #16a34a #facc15].freeze
    MAX_POINTS = 1500          # per stroke
    MAX_LIVE_POINTS = 200      # per in-progress message
    MAX_LAYER_POINTS = 60_000  # per layer (roughly 1 MB of JSON)
    MAX_ID_LENGTH = 64         # client and stroke ids, echoed back to the screens

    attr_reader :session

    def initialize(session)
      @session = session
    end

    # Which stop the projector is on; slide strokes are kept only for the stop they were drawn on.
    def self.stop_key(session)
      [ session.current_set_item_id, session.current_section_index, session.current_chunk_index ].join("-")
    end

    # A stroke from the client, or nil if it isn't one. Unknown colours fall back to the first.
    def self.clean_stroke(raw, max_points: MAX_POINTS)
      return unless raw.is_a?(Hash)

      raw = raw.stringify_keys
      tool = raw["t"].to_s
      return unless TOOLS.include?(tool)

      color = raw["c"].to_s.downcase
      color = COLORS.first unless COLORS.include?(color)
      points = clean_points(raw["p"], max_points)
      return if points.empty?

      { "t" => tool, "c" => color, "p" => points }
    end

    def self.clean_points(raw, max)
      Array(raw).first(max).filter_map do |pt|
        next unless pt.is_a?(Array) && pt.size == 2 && pt.all?(Numeric)

        pt.map { |v| v.to_f.clamp(0.0, 1.0).round(4) }
      end
    end

    def stop_key = self.class.stop_key(session)

    def slide_strokes = session.whiteboard_slide_stop == stop_key ? session.whiteboard_slide : []

    # "Romanos 11:33 · Page 2 of 4": what the projector shows, for the speaker view's Now line
    # (so Next is visible even while the whiteboard covers the slide).
    def stop_label
      helpers = ApplicationController.helpers
      helpers.strip_tags(helpers.operator_stop_label(session).to_s)
    end

    # Everything a screen needs to draw the whiteboard; sent on subscribe and after each change.
    def state
      { type: "state", mode: session.whiteboard_mode, dark: session.whiteboard_dark, blanked: session.blanked,
        stop: stop_key, label: stop_label, board: session.whiteboard_board, slide: slide_strokes }
    end

    # Put the whiteboard (or slide drawing) on the projector. Bumps position_version and
    # re-broadcasts the frames so the band view shows that the whiteboard is on.
    def start!(mode)
      return unless MODES.include?(mode.to_s)

      change_mode(mode.to_s)
    end

    # Back to the slide. Board strokes stay for next time; slide strokes go.
    def stop!
      change_mode(nil, whiteboard_slide: [], whiteboard_slide_stop: nil)
    end

    def dark!(value)
      locked { session.update_columns(whiteboard_dark: ActiveModel::Type::Boolean.new.cast(value) || false) }
      broadcast(state)
    end

    # Store a finished stroke on the current mode's layer and send it to every screen. Returns the
    # stored stroke, or nil when nothing is on or the stroke is invalid or the layer is full.
    def add_stroke!(raw, src: nil, id: nil)
      stroke = self.class.clean_stroke(raw)
      return if stroke.nil?

      layer = nil
      stored = locked do
        layer = session.whiteboard_mode
        next false if layer.nil?

        if layer == "board"
          next false if points_in(session.whiteboard_board) + stroke["p"].size > MAX_LAYER_POINTS

          session.update_columns(whiteboard_board: session.whiteboard_board + [ stroke ])
        else
          current = slide_strokes
          next false if points_in(current) + stroke["p"].size > MAX_LAYER_POINTS

          session.update_columns(whiteboard_slide: current + [ stroke ], whiteboard_slide_stop: stop_key)
        end
      end
      unless stored
        broadcast(state) # rejected: resync the speaker, who already drew it locally
        return
      end

      broadcast({ type: "stroke", layer:, stroke:, src: short(src), id: short(id) })
      stroke
    end

    # Points of a stroke still being drawn: relayed to the screens, never stored.
    def relay_live!(raw, src: nil, id: nil)
      return if session.whiteboard_mode.nil?

      stroke = self.class.clean_stroke(raw, max_points: MAX_LIVE_POINTS)
      return if stroke.nil?

      broadcast(stroke.merge(type: "live", src: short(src), id: short(id)))
    end

    def undo!
      locked do
        if session.whiteboard_mode == "board"
          session.update_columns(whiteboard_board: session.whiteboard_board[0...-1])
        elsif session.whiteboard_mode == "slide"
          session.update_columns(whiteboard_slide: slide_strokes[0...-1], whiteboard_slide_stop: stop_key)
        end
      end
      broadcast(state)
    end

    def clear!
      locked do
        if session.whiteboard_mode == "board"
          session.update_columns(whiteboard_board: [])
        elsif session.whiteboard_mode == "slide"
          session.update_columns(whiteboard_slide: [], whiteboard_slide_stop: nil)
        end
      end
      broadcast(state)
    end

    # After any position or blank change. Slide strokes from the stop the service just left are
    # dropped, and the screens told which stop is showing so they drop them too.
    def broadcast_position
      # Straight in SQL: this row may have been loaded before the speaker started drawing.
      LiveSession.where(id: session.id).where.not(whiteboard_slide_stop: [ nil, stop_key ])
                 .update_all("whiteboard_slide = '[]'::jsonb, whiteboard_slide_stop = NULL")
      broadcast({ type: "position", stop: stop_key, label: stop_label, blanked: session.blanked })
    end

    def broadcast_ended
      broadcast({ type: "ended" })
    end

    private

    # Only while the service is live: after it ends, a re-broadcast frame would replace the
    # "ended" screen on the projector and the band view.
    def change_mode(mode, **extra)
      return unless session.active?

      locked do
        session.update_columns(whiteboard_mode: mode, position_version: session.position_version + 1, **extra)
      end
      Corobook::LiveBroadcast.position(session)
      broadcast(state)
    end

    def locked(&) = session.with_lock(&)

    def points_in(strokes) = strokes.sum { |s| Array(s["p"]).size }

    def short(value) = value.to_s.first(MAX_ID_LENGTH)

    def broadcast(payload)
      WhiteboardChannel.broadcast_to(session, payload)
    end
  end
end

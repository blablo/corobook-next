require "test_helper"

class Corobook::WhiteboardTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @church = Church.create!(name: "Central")
    @set = @church.service_sets.create!(name: "Domingo")
    @set.set_items.create!(position: 0, item_type: "song",
                           song: @church.songs.create!(title: "Uno", chordpro_source: "{sov: V1}\nUno\n{eov}"))
    @set.set_items.create!(position: 1, item_type: "text_slide", text_slide: @church.text_slides.create!(title: "Credo", reusable: true))
    @session = LiveSession.launch(@set)
    @board = Corobook::Whiteboard.new(@session)
  end

  def stroke(points = [ [ 0.1, 0.2 ], [ 0.3, 0.4 ] ], tool: "pen", color: "#2563eb") = { "t" => tool, "c" => color, "p" => points }
  def stream = WhiteboardChannel.broadcasting_for(@session)

  test "launch issues a speaker token and ending revokes it and turns the whiteboard off" do
    assert @session.speaker_token.present?
    @board.start!("board")
    @session.end!
    assert_nil @session.reload.speaker_token
    assert_nil @session.whiteboard_mode
  end

  test "clean_stroke keeps valid points, clamps them, and rejects unknown tools" do
    cleaned = Corobook::Whiteboard.clean_stroke(stroke([ [ 1.5, -2 ], [ 0.123456, 0.5 ], "x", [ 1 ] ], color: "#ABCDEF"))
    assert_equal [ [ 1.0, 0.0 ], [ 0.1235, 0.5 ] ], cleaned["p"]
    assert_equal "#111827", cleaned["c"], "an unknown colour falls back to the first"
    assert_nil Corobook::Whiteboard.clean_stroke(stroke(tool: "spray"))
    assert_nil Corobook::Whiteboard.clean_stroke(stroke([]))
    assert_equal Corobook::Whiteboard::MAX_POINTS,
                 Corobook::Whiteboard.clean_stroke(stroke(Array.new(2000) { [ 0.5, 0.5 ] }))["p"].size
  end

  test "start and stop switch the mode, bump the frame version and broadcast the state" do
    version = @session.position_version
    assert_broadcasts(stream, 2) { @board.start!("board") } # position + state
    assert_equal "board", @session.reload.whiteboard_mode
    assert_equal version + 1, @session.position_version
    @board.stop!
    assert_nil @session.reload.whiteboard_mode
    assert_nil @board.start!("spray")
    assert_nil @session.reload.whiteboard_mode
  end

  test "strokes go to the current mode's layer and nothing is stored while it is off" do
    assert_nil @board.add_stroke!(stroke)
    @board.start!("board")
    assert @board.add_stroke!(stroke, src: "tab", id: "tab-1")
    assert_equal 1, @session.reload.whiteboard_board.size
    assert_empty @session.whiteboard_slide
  end

  test "the board survives stop and start; undo and clear act on it" do
    @board.start!("board")
    2.times { @board.add_stroke!(stroke) }
    @board.stop!
    @board.start!("board")
    assert_equal 2, @board.state[:board].size
    @board.undo!
    assert_equal 1, @session.reload.whiteboard_board.size
    @board.clear!
    assert_empty @session.reload.whiteboard_board
  end

  test "slide strokes belong to their stop: a move drops them, and stopping clears them" do
    @board.start!("slide")
    @board.add_stroke!(stroke)
    assert_equal 1, @board.state[:slide].size

    @session.update!(current_section_index: 1, position_version: @session.position_version + 1)
    assert_empty Corobook::Whiteboard.new(@session).state[:slide]

    board = Corobook::Whiteboard.new(@session)
    board.add_stroke!(stroke)
    assert_equal 1, @session.reload.whiteboard_slide.size, "a new stop starts a fresh drawing"
    board.stop!
    assert_empty @session.reload.whiteboard_slide
  end

  test "a full layer refuses more strokes and resyncs the speaker" do
    @board.start!("board")
    big = stroke(Array.new(1500) { [ 0.5, 0.5 ] })
    40.times { @board.add_stroke!(big) }
    assert_broadcasts(stream, 1) { assert_nil @board.add_stroke!(big) }
    assert_equal 40, @session.reload.whiteboard_board.size
  end

  test "live points are relayed, never stored" do
    @board.start!("slide")
    assert_broadcasts(stream, 1) { @board.relay_live!(stroke, src: "tab", id: "tab-1") }
    assert_empty @session.reload.whiteboard_slide
  end

  test "drawing never bumps lock_version, so an operator move can't go stale" do
    lock = @session.lock_version
    @board.start!("board")
    @board.add_stroke!(stroke)
    @board.undo!
    assert_equal lock, @session.reload.lock_version
  end

  test "a position broadcast tells the screens which stop is showing" do
    assert_broadcast_on(stream, { type: "position", stop: @board.stop_key, label: "Uno · Title", blanked: false }) do
      Corobook::LiveBroadcast.position(@session)
    end
  end

  test "moving off a slide drops its marks, so coming back to it shows a clean slide" do
    @board.start!("slide")
    @board.add_stroke!(stroke)
    first = [ @session.current_section_index, @session.current_chunk_index ]

    @session.update!(current_section_index: 1, position_version: @session.position_version + 1)
    Corobook::LiveBroadcast.position(@session)
    @session.update!(current_section_index: first[0], position_version: @session.position_version + 1)
    Corobook::LiveBroadcast.position(@session)

    assert_empty @session.reload.whiteboard_slide
    assert_empty Corobook::Whiteboard.new(@session).state[:slide]
  end

  test "ending the service tells the screens and forgets the drawings" do
    @board.start!("board")
    @board.add_stroke!(stroke)
    @session.end!
    assert_broadcast_on(stream, { type: "ended" }) { Corobook::LiveBroadcast.ended(@session) }
    assert_empty @session.reload.whiteboard_board
  end

  test "start and stop do nothing once the service has ended" do
    @session.end!
    version = @session.position_version
    assert_no_broadcasts(stream) { Corobook::Whiteboard.new(@session).stop! }
    assert_equal version, @session.reload.position_version
  end

  test "stroke ids echoed to the screens are kept short, and non-hash strokes are ignored" do
    @board.start!("board")
    assert_broadcast_on(stream, { type: "stroke", layer: "board", stroke: Corobook::Whiteboard.clean_stroke(stroke),
                                  src: "s" * 64, id: "i" * 64 }) do
      @board.add_stroke!(stroke, src: "s" * 500, id: "i" * 500)
    end
    assert_nil Corobook::Whiteboard.clean_stroke([ [ 0.1, 0.2 ] ])
  end
end

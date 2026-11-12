require "test_helper"

class WhiteboardChannelTest < ActionCable::Channel::TestCase
  setup do
    @church = Church.create!(name: "Central")
    @set = @church.service_sets.create!(name: "Domingo")
    @set.set_items.create!(position: 0, item_type: "song", song: @church.songs.create!(title: "Uno", chordpro_source: "[C]x"))
    @session = LiveSession.launch(@set)
  end

  def stroke = { "t" => "pen", "c" => "#2563eb", "p" => [ [ 0.1, 0.1 ], [ 0.2, 0.2 ] ] }

  test "the speaker subscribes with the speaker token and gets the current state" do
    subscribe speaker: @session.speaker_token
    assert subscription.confirmed?
    assert_has_stream_for @session
    assert_equal "state", transmissions.last["type"]
    assert_nil transmissions.last["mode"]
  end

  test "a screen subscribes with the signed viewer key" do
    subscribe viewer: @session.whiteboard_viewer_key
    assert subscription.confirmed?
    assert_has_stream_for @session
  end

  test "a wrong token, a forged key or an ended service is rejected" do
    subscribe speaker: "nope"
    assert subscription.rejected?

    subscribe viewer: @session.id.to_s
    assert subscription.rejected?

    key = @session.whiteboard_viewer_key
    travel 2.days do
      subscribe viewer: key
      assert subscription.rejected?, "the viewer key expires"
    end

    token = @session.speaker_token
    @session.end!
    subscribe speaker: token
    assert subscription.rejected?
  end

  test "the speaker starts the whiteboard and draws; the stroke is stored and broadcast" do
    subscribe speaker: @session.speaker_token
    perform :start, mode: "board"
    assert_broadcasts(WhiteboardChannel.broadcasting_for(@session), 1) do
      perform :stroke, src: "tab", id: "tab-1", stroke: stroke
    end
    assert_equal [ stroke ], @session.reload.whiteboard_board
    perform :undo
    assert_empty @session.reload.whiteboard_board
    perform :stop
    assert_nil @session.reload.whiteboard_mode
  end

  test "a viewer cannot draw or switch the whiteboard on" do
    subscribe viewer: @session.whiteboard_viewer_key
    perform :start, mode: "board"
    perform :stroke, stroke: stroke
    assert_nil @session.reload.whiteboard_mode
    assert_empty @session.whiteboard_board
  end

  test "the speaker's actions stop working once the service ends" do
    subscribe speaker: @session.speaker_token
    perform :start, mode: "board"
    @session.end!
    perform :stroke, stroke: stroke
    perform :start, mode: "slide"
    assert_empty @session.reload.whiteboard_board
    assert_nil @session.whiteboard_mode
  end
end

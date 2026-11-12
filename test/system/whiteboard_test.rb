require "application_system_test_case"

class WhiteboardSystemTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central")
    @set = @church.service_sets.create!(name: "Domingo")
    @set.set_items.create!(position: 0, item_type: "song",
                           song: @church.songs.create!(title: "Uno", chordpro_source: "{sov: V1}\nUno\n{eov}"))
    @session = LiveSession.launch(@set)
  end

  def wait_until(seconds = 5)
    deadline = Time.current + seconds
    sleep 0.1 until yield || Time.current > deadline
  end

  test "the speaker puts a whiteboard on the projector, draws on it, and takes it off" do
    using_session(:projector) do
      visit projector_path(@session.projector_token)
      assert_selector "[data-role=projector-frame]"
      assert_selector "[data-role=whiteboard-layer]", visible: :hidden
    end

    visit speaker_path(@session.speaker_token)
    find("[data-role=start-board]").click
    assert_selector "[data-role=speaker-status]", text: "Whiteboard on the projector"
    assert_selector "[data-role=speaker-tools]"
    assert_no_selector "[data-role=speaker-next]" # Next/Back make room for the board

    canvas = find("[data-role=whiteboard-canvas]")
    page.driver.browser.action.move_to(canvas.native).click_and_hold.move_by(60, 20).move_by(60, -10).release.perform
    wait_until { @session.reload.whiteboard_board.any? }
    assert_equal 1, @session.reload.whiteboard_board.size

    using_session(:projector) { assert_selector "[data-role=whiteboard-layer]", visible: true }

    find("[data-role=speaker-stop]").click
    assert_selector "[data-role=start-board]"
    assert_selector "[data-role=speaker-next]"
    using_session(:projector) { assert_selector "[data-role=whiteboard-layer]", visible: :hidden }
    assert_nil @session.reload.whiteboard_mode
    assert_equal 1, @session.whiteboard_board.size, "the board is kept for next time"
  end

  test "Next and Back on the speaker view move the projector" do
    set = @church.service_sets.create!(name: "Tarde")
    set.set_items.create!(position: 0, item_type: "song",
                          song: @church.songs.create!(title: "Himno", chordpro_source: "{sov: V1}\nPrimera línea\n{eov}"))
    @session.end!
    session = LiveSession.launch(set)

    using_session(:projector) do
      visit projector_path(session.projector_token)
      assert_selector "[data-role=projector-frame]", text: "Himno"
    end

    visit speaker_path(session.speaker_token)
    find("[data-role=speaker-next]").click
    assert_selector "[data-role=speaker-now]", text: /V1|Verse/i
    using_session(:projector) { assert_selector "[data-role=projector-frame]", text: "Primera línea" }

    find("[data-role=speaker-back]").click
    using_session(:projector) { assert_selector "[data-role=projector-frame]", text: "Himno" }
  end
end

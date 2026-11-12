require "test_helper"

class SpeakerViewTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    @editor = User.create!(church: @church, email: "op@example.com", password: "secret123", role: "editor")
    @set = @church.service_sets.create!(name: "Domingo")
    @set.set_items.create!(position: 0, item_type: "song",
                           song: @church.songs.create!(title: "Uno", chordpro_source: "{sov: V1}\nUno\n{eov}"))
    @session = LiveSession.launch(@set)
  end

  def sign_in = post(login_path, params: { church_id: @church.id, email: @editor.email, password: "secret123" })

  test "the speaker link opens the speaker view without signing in" do
    get speaker_path(@session.speaker_token)
    assert_response :success
    assert_select "[data-role=speaker][data-whiteboard-speaker-value='#{@session.speaker_token}']"
    assert_select "[data-role=speaker-stage] [data-role=projector-frame]"
    assert_select "[data-role=start-board]"
    assert_select "[data-role=start-slide]"
    assert_select "[data-role=whiteboard-canvas]"
  end

  test "Next and Back on the speaker view move the service for every screen" do
    get speaker_path(@session.speaker_token)
    assert_select "[data-role=speaker-next]"
    assert_select "[data-role=speaker-back]"
    assert_select "[data-role=speaker-now]", text: "Uno · Title"

    patch speaker_advance_path(@session.speaker_token)
    assert_response :no_content
    assert_equal 1, @session.reload.current_section_index
    patch speaker_back_path(@session.speaker_token)
    assert_equal 0, @session.reload.current_section_index
  end

  test "Back at the first stop and Next at the last do nothing" do
    version = @session.position_version
    patch speaker_back_path(@session.speaker_token)
    assert_response :no_content
    assert_equal version, @session.reload.position_version

    2.times { patch speaker_advance_path(@session.speaker_token) }
    assert_response :no_content
    assert_equal version + 1, @session.reload.position_version, "only one more stop (the verse)"
  end

  test "the Now line is plain text, entities and all" do
    @session.current_item.update!(title: %(Tom & Jerry "Live"))
    get speaker_path(@session.speaker_token)
    assert_select "[data-role=speaker-now]", text: %(Tom & Jerry "Live" · Title)
    assert_equal %(Tom & Jerry "Live" · Title), Corobook::Whiteboard.new(@session.reload).stop_label
  end

  test "the Now line names an auto-advancing slide by its title only" do
    slide = @church.text_slides.create!(title: "Anuncios", reusable: true, auto_advance_seconds: 8,
                                        pages: [ { "body_markdown" => "a" }, { "body_markdown" => "b" } ])
    item = @set.set_items.create!(position: 1, item_type: "text_slide", text_slide: slide)
    @session.update!(current_set_item: item, current_section_index: 0)
    assert_equal "Anuncios", Corobook::Whiteboard.new(@session).stop_label
  end

  test "Next and Back stop working with the speaker link" do
    token = @session.speaker_token
    @session.end!
    patch speaker_advance_path(token)
    assert_response :not_found
    patch speaker_advance_path("nope")
    assert_response :not_found
  end

  test "the speaker link stops working when the service ends" do
    token = @session.speaker_token
    @session.end!
    get speaker_path(token)
    assert_response :not_found
  end

  test "the projector carries a whiteboard layer with a viewer key, not the speaker token" do
    get projector_path(@session.projector_token)
    assert_response :success
    assert_select "[data-role=projector-root][data-whiteboard-viewer-value]"
    assert_select "[data-role=projector-root] [data-role=whiteboard-layer][hidden]"
    assert_not_includes response.body, @session.speaker_token
  end

  test "the operator offers the speaker link and can stop the whiteboard" do
    sign_in
    get operator_path(@session)
    assert_select "[data-role=speaker-view]"
    assert_select "[data-role=speaker-modal] [data-role=speaker-url]", text: /#{Regexp.escape(speaker_path(@session.speaker_token))}/
    assert_select "[data-role=whiteboard-banner][hidden] [data-role=stop-whiteboard]"

    Corobook::Whiteboard.new(@session).start!("board")
    patch operator_whiteboard_stop_path(@session)
    assert_redirected_to operator_path(@session)
    assert_nil @session.reload.whiteboard_mode
  end

  test "a session launched before the whiteboard gets a speaker token when the operator opens it" do
    @session.update_column(:speaker_token, nil)
    sign_in
    get operator_path(@session)
    assert @session.reload.speaker_token.present?
  end

  test "the band view says when the whiteboard is on" do
    Corobook::Whiteboard.new(@session).start!("board")
    get musician_path(@session.musician_token)
    assert_select "[data-role=whiteboard-note]"
  end

  test "another church's operator cannot stop this whiteboard" do
    other = Church.create!(name: "Norte")
    User.create!(church: other, email: "x@example.com", password: "secret123", role: "editor")
    post login_path, params: { church_id: other.id, email: "x@example.com", password: "secret123" }
    Corobook::Whiteboard.new(@session).start!("board")
    patch operator_whiteboard_stop_path(@session)
    assert_response :not_found
    assert_equal "board", @session.reload.whiteboard_mode
  end
end

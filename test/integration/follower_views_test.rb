require "test_helper"

class FollowerViewsTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central", ccli_license_number: "9876543")
    @song = @church.songs.create!(title: "Himno", song_key: "G", chordpro_source: "{key: G}\n[G]Hola [C]mundo")
    @set = @church.service_sets.create!(name: "Domingo")
    @item = @set.set_items.create!(position: 0, item_type: "song", song: @song)
    @session = LiveSession.launch(@set)
  end

  test "the projector view renders for a valid token" do
    get projector_path(@session.projector_token)
    assert_response :success
    assert_select "[data-role=projector-frame]"
    assert_select "[data-role=projector-lyrics]", text: /Hola mundo/
  end

  test "a bad projector token returns 404" do
    get projector_path("not-a-real-token")
    assert_response :not_found
  end

  test "an ended session's token returns 404" do
    token = @session.projector_token
    @session.end!
    get projector_path(token)
    assert_response :not_found
  end

  test "two musicians on different keys each see their own chords" do
    get musician_path(@session.musician_token, key: "A")
    assert_response :success
    assert_select "[data-role=chord]", text: "A"

    get musician_path(@session.musician_token, key: "C")
    assert_response :success
    assert_select "[data-role=chord]", text: "C"
  end

  test "the musician view 404s on a bad token" do
    get musician_path("nope")
    assert_response :not_found
  end
end

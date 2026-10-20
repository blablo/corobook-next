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
    @session.update!(current_section_index: 1) # past the title slide, onto the first lyric section
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
    @session.update!(current_section_index: 1) # past the title slide, onto the first lyric section
    get musician_path(@session.musician_token, key: "A")
    assert_response :success
    assert_select "[data-role=chord]", text: "A"

    get musician_path(@session.musician_token, key: "C")
    assert_response :success
    assert_select "[data-role=chord]", text: "C"
  end

  test "the first slide of a song is its title with licensing credits" do
    @song.update!(author: "J. Autor", copyright_line: "© 2020 Casa", ccli_song_number: "12345")
    # Session starts at section 0 = the title slide.
    get projector_path(@session.projector_token)
    assert_response :success
    assert_select "[data-role=projector-title]"
    assert_select "[data-role=title]", text: "Himno"
    assert_select "[data-role=title-credits]", text: /J\. Autor/
    assert_select "[data-role=title-credits]", text: /CCLI #12345/
    # The lyrics are NOT on the title slide.
    assert_select "[data-role=projector-lyrics]", count: 0
  end

  test "the musician frame honors arrangement order, not raw section order" do
    # Song whose arrangement puts the Chorus first (its raw section 0 is a chords-only intro).
    song = @church.songs.create!(title: "Razones", song_key: "A",
      chordpro_source: "{key: A}\n{sov: Intro}\n[A] [E]\n{eov}\n{soc: Chorus}\nBendice alma mía\n{eov}",
      arrangement: [ "Chorus" ])
    set = @church.service_sets.create!(name: "Otro")
    set.set_items.create!(position: 0, item_type: "song", song: song)
    session = LiveSession.launch(set)
    session.update!(current_section_index: 1) # first ordered lyric section

    get musician_path(session.musician_token)
    assert_response :success
    # Must show the arrangement's first section (Chorus lyrics), NOT the raw intro.
    assert_select "[data-role=musician-frame]", text: /Bendice alma/
    assert_select "[data-role=musician-frame]", text: /Intro/, count: 0
  end

  test "the musician view 404s on a bad token" do
    get musician_path("nope")
    assert_response :not_found
  end
end

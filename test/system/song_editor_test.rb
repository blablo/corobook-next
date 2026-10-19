require "application_system_test_case"

class SongEditorTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central")
    @editor = User.create!(church: @church, email: "editor@example.com", password: "secret123", role: "editor")
    visit login_path
    select @church.name, from: "Church"
    fill_in "Email", with: @editor.email
    fill_in "Password", with: "secret123"
    click_on "Sign in"
    assert_selector "[data-role=home]" # landed on home after login
  end

  test "a song with a malformed chord persists and shows an inline parse warning" do
    visit new_song_path
    assert_text "New song"
    fill_in "Title", with: "Canto con error"

    # Power-user path: switch to Advanced (raw ChordPro) and type source directly.
    click_on "Advanced (ChordPro)"
    fill_in "ChordPro source", with: "[Fm#]Hola mundo\n{chorus}"

    # Arrangement lives in a collapsed advanced section — open it via its toggle.
    find(".collapse", text: "Arrangement order").find("input[type=checkbox]", visible: :all).click
    fill_in "song[arrangement_text]", with: "Verso\nCoro"
    click_on "Create song"

    assert_text "Song created."
    assert_selector "[data-role=parse-warning]", text: "x_corobook_parse_warning"
    assert_selector "[data-role=arrangement]", text: "Verso → Coro"

    song = @church.songs.find_by(title: "Canto con error")
    assert_includes song.chordpro_source, "[Fm#]"
    assert_equal %w[Verso Coro], song.arrangement
  end

  test "the visual editor builds ChordPro without the user typing syntax" do
    visit new_song_path
    assert_text "New song"
    fill_in "Title", with: "Canto visual"

    # Visual mode is the default. Add a chorus section (prompts for the first line).
    accept_prompt(with: "Santo es el Señor") do
      click_on "+ Chorus"
    end

    # The hidden canonical field now holds serialized ChordPro with section directives.
    source = find("input[data-song-editor-target=source]", visible: false).value
    assert_includes source, "{soc}"
    assert_includes source, "Santo es el Señor"
    assert_includes source, "{eoc}"

    click_on "Create song"
    assert_text "Song created."

    song = @church.songs.find_by(title: "Canto visual")
    assert_includes song.chordpro_source, "Santo es el Señor"
    # round-trips through the server parser into a chorus section
    assert_equal "chorus", song.parsed.sections.first["kind"]
  end
end

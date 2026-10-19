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

    # Visual mode is the default. Add a chorus section — it creates an editable line.
    click_on "+ Chorus"

    # Type lyrics directly into the inline contenteditable lyric line (no prompt).
    line = find(".lyric-edit")
    line.click
    line.send_keys("Santo es el Señor")
    # Enter adds a new line below and moves the caret there.
    line.send_keys(:enter)
    assert_selector ".lyric-edit", count: 2
    find(:css, ".lyric-edit", match: :first) # ensure rendered
    page.driver.browser.switch_to.active_element.send_keys("Digno de gloria")
    # blur to flush the input handler
    find("body").click

    # The hidden canonical field now holds serialized ChordPro with section directives.
    source = find("input[data-song-editor-target=source]", visible: false).value
    assert_includes source, "Digno de gloria"
    assert_includes source, "{soc}"
    assert_includes source, "Santo es el Señor"
    assert_includes source, "{eoc}"

    # After typing, clicking the line opens the chord picker; picking a chord places it
    # (regression: dynamically-injected picker chips must be clickable without a Stimulus race).
    find(".lyric-edit", match: :first).click
    assert_selector ".song-picker"
    # The builder can reach ANY chord, not just key chords — build F#m7 via root + suffix.
    within(".song-picker") do
      find(".rootbtn[data-root='F#']").click
      find(".sufbtn[data-suf='m7']").click
    end
    assert_no_selector ".song-picker"
    source = find("input[data-song-editor-target=source]", visible: false).value
    assert_includes source, "[F#m7]"

    # Remove a wrongly-placed chord by clicking its pill.
    find(".chord-pill").click
    assert_no_match(/\[[A-G][^\]]*\]/, find("input[data-song-editor-target=source]", visible: false).value)

    # Re-place one so the saved song carries a chord.
    find(".lyric-edit", match: :first).click
    within(".song-picker") { first(".chip").click }
    assert_match(/\[[A-G][^\]]*\]/, find("input[data-song-editor-target=source]", visible: false).value)

    click_on "Create song"
    assert_text "Song created."

    song = @church.songs.find_by(title: "Canto visual")
    assert_includes song.chordpro_source, "Santo es el Señor"
    assert_match(/\[[A-G][^\]]*\]/, song.chordpro_source)
    # round-trips through the server parser into a chorus section
    assert_equal "chorus", song.parsed.sections.first["kind"]
  end
end

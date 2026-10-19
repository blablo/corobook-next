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
    assert_text "Signed in as editor@example.com"
  end

  test "a song with a malformed chord persists and shows an inline parse warning" do
    visit new_song_path
    assert_text "New song"
    fill_in "Title", with: "Canto con error"
    fill_in "ChordPro source", with: "[Fm#]Hola mundo\n{chorus}"
    fill_in "Arrangement (section labels, one per line — empty = section order)", with: "Verso\nCoro"
    click_on "Create Song"

    assert_text "Song created."
    assert_selector "[data-role=parse-warning]", text: "x_corobook_parse_warning"
    assert_selector "[data-role=arrangement]", text: "Verso → Coro"

    song = @church.songs.find_by(title: "Canto con error")
    assert_includes song.chordpro_source, "[Fm#]"
    assert_equal %w[Verso Coro], song.arrangement
  end
end

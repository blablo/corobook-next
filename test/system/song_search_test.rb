require "application_system_test_case"

class SongSearchTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central")
    @editor = User.create!(church: @church, email: "editor@example.com", password: "secret123", role: "editor")
    @church.songs.create!(title: "Cuán grande es Él", chordpro_source: "Señor mi [G]Dios al contemplar")
    @church.songs.create!(title: "Sublime gracia", chordpro_source: "Sublime gracia del Señor")
    visit login_path
    select @church.name, from: "Church"
    fill_in "Email", with: @editor.email
    fill_in "Password", with: "secret123"
    click_on "Sign in"
    assert_selector "[data-role=home]" # landed on home after login
  end

  test "searching by a lyric word returns the matching song" do
    visit songs_path
    fill_in "q", with: "contemplar"
    find("[data-role=song-search]").native.send_keys(:return)

    within "[data-role=song-results]" do
      assert_text "Cuán grande es Él"
      assert_no_text "Sublime gracia"
    end
  end
end

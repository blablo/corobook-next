require "application_system_test_case"

class MusicianViewTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central")
    @editor = User.create!(church: @church, email: "editor@example.com", password: "secret123", role: "editor")
    @song = @church.songs.create!(title: "Himno", song_key: "G", chordpro_source: "{key: G}\n[G]Hola [C]mundo")
    visit login_path
    select @church.name, from: "Church"
    fill_in "Email", with: @editor.email
    fill_in "Password", with: "secret123"
    click_on "Sign in"
    assert_text "Signed in as #{@editor.email}"
  end

  test "the musician view shows chords at the source key" do
    visit song_path(@song)
    within "[data-role=musician-preview]" do
      assert_selector "[data-role=chord]", text: "G"
      assert_selector "[data-role=chord]", text: "C"
      assert_selector "[data-role=key-badge]", text: "Key G"
    end
  end

  test "transposing to a target key changes the displayed chords and badge" do
    visit song_path(@song, key: "A")
    within "[data-role=musician-preview]" do
      assert_selector "[data-role=chord]", text: "A"
      assert_selector "[data-role=chord]", text: "D"
      assert_selector "[data-role=key-badge]", text: "Key A"
      assert_no_selector "[data-role=chord]", text: "G"
    end
  end
end

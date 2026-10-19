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
    assert_selector "[data-role=home]" # landed on home after login
  end

  test "the musician view shows chords at the source key" do
    visit song_path(@song)
    within "[data-role=musician-preview]" do
      assert_selector "[data-role=chord]", text: "G"
      assert_selector "[data-role=chord]", text: "C"
    end
    assert_selector "[data-role=key-badge]", text: "Key G"
  end

  test "transposing to a target key changes the displayed chords and badge" do
    visit song_path(@song, key: "A")
    within "[data-role=musician-preview]" do
      assert_selector "[data-role=chord]", text: "A"
      assert_selector "[data-role=chord]", text: "D"
      assert_no_selector "[data-role=chord]", text: "G"
    end
    assert_selector "[data-role=key-badge]", text: "Key A"
  end

  test "a song whose arrangement labels don't match its sections still shows the sections" do
    # Legacy data: arrangement references English labels but sections are labelled in Spanish.
    song = @church.songs.create!(
      title: "Legado", song_key: "C",
      chordpro_source: "{key: C}\n{sov: Verso 1}\n[C]Gloria a [G]Dios\n{eov}",
      arrangement: [ "Verse 1", "Verse 2" ]
    )
    visit song_path(song)
    within "[data-role=musician-preview]" do
      assert_selector "[data-role=chord]", text: "C"
      assert_selector "[data-role=chord]", text: "G"
    end
    assert_selector "[data-role=section-label]", text: "VERSO 1"
  end

  test "sections are printed in arrangement order, repeating a reused section" do
    song = @church.songs.create!(
      title: "Orden", song_key: "C",
      chordpro_source: "{key: C}\n{sov: Verse 1}\n[C]uno\n{eov}\n{soc: Chorus 1}\n[G]coro\n{eoc}",
      arrangement: [ "Verse 1", "Chorus 1", "Chorus 1" ]
    )
    visit song_path(song)
    labels = all("[data-role=section-label]").map(&:text)
    assert_equal [ "VERSE 1", "CHORUS 1", "CHORUS 1" ], labels
  end
end

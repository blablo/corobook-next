require "application_system_test_case"

class ProjectorNoticeTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central", ccli_license_number: "9876543")
    @editor = User.create!(church: @church, email: "editor@example.com", password: "secret123", role: "editor")
    sign_in_editor
  end

  def sign_in_editor
    visit login_path
    select @church.name, from: "Church"
    fill_in "Email", with: @editor.email
    fill_in "Password", with: "secret123"
    click_on "Sign in"
    assert_text "Signed in as #{@editor.email}" # block until the session is established
  end

  def make_song(status, **attrs)
    @church.songs.create!({ title: "Song", chordpro_source: "Gloria a Dios", copyright_status: status }.merge(attrs))
  end

  test "a copyrighted, licensed song shows the copyright notice" do
    song = make_song("copyrighted", copyright_line: "© 2020 Autor", ccli_song_number: 12345)
    visit song_path(song)
    assert_selector "[data-role=copyright-notice]", text: "CCLI License #9876543"
    assert_no_selector "[data-role=copyright-warning]"
  end

  test "a public-domain song shows no notice and no warning" do
    song = make_song("public_domain")
    visit song_path(song)
    assert_no_selector "[data-role=copyright-notice]"
    assert_no_selector "[data-role=copyright-warning]"
  end

  test "an unknown-status song suppresses the notice and warns the editor" do
    song = make_song("unknown")
    visit song_path(song)
    assert_no_selector "[data-role=copyright-notice]"
    assert_selector "[data-role=copyright-warning]", text: "unknown"
  end

  test "a copyrighted song with no church license suppresses and warns" do
    @church.update!(ccli_license_number: nil)
    song = make_song("copyrighted", copyright_line: "© 2020 Autor")
    visit song_path(song)
    assert_no_selector "[data-role=copyright-notice]"
    assert_selector "[data-role=copyright-warning]", text: "no CCLI license"
  end
end

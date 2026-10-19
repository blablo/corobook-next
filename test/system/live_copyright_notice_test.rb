require "application_system_test_case"

class LiveCopyrightNoticeTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central", ccli_license_number: "9876543")
    @song = @church.songs.create!(
      title: "Cuan grande es Él", copyright_status: "copyrighted",
      copyright_line: "© 1953 Stuart K. Hine", ccli_song_number: 14181,
      chordpro_source: "Señor mi Dios"
    )
    @set = @church.service_sets.create!(name: "Domingo")
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
    @session = LiveSession.launch(@set)
  end

  test "the live projector shows the composed CCLI notice for a licensed copyrighted song" do
    visit projector_path(@session.projector_token)
    notice = find("[data-role=copyright-notice]")
    assert_match "© 1953 Stuart K. Hine", notice.text
    assert_match "CCLI Song #14181", notice.text
    assert_match "CCLI License #9876543", notice.text
  end
end

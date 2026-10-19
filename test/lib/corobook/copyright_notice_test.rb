require "test_helper"

class Corobook::CopyrightNoticeTest < ActiveSupport::TestCase
  setup { @church = Church.create!(name: "Central") }

  def song(**attrs)
    @church.songs.build({ title: "X", chordpro_source: "Hola" }.merge(attrs))
  end

  test "shows a composed notice for a copyrighted song when the church is licensed" do
    s = song(copyright_status: "copyrighted", copyright_line: "© 2020 Autor", ccli_song_number: 12345)
    result = Corobook::CopyrightNotice.for(s, church_license: "9876543")
    assert result.show?
    assert_includes result.text, "© 2020 Autor"
    assert_includes result.text, "CCLI Song #12345"
    assert_includes result.text, "CCLI License #9876543"
  end

  test "suppresses the notice entirely for a public-domain song" do
    result = Corobook::CopyrightNotice.for(song(copyright_status: "public_domain"), church_license: "9876543")
    assert_equal :suppress, result.state
    assert_not result.show?
    assert_not result.warn?
  end

  test "warns (not shows) for a copyrighted song when no license is on file" do
    result = Corobook::CopyrightNotice.for(song(copyright_status: "copyrighted"), church_license: nil)
    assert result.warn?
    assert_not result.show?
    assert_match(/no CCLI license/i, result.warning)
  end

  test "warns for unknown copyright status" do
    result = Corobook::CopyrightNotice.for(song(copyright_status: "unknown"), church_license: "9876543")
    assert result.warn?
    assert_not result.show?
    assert_match(/unknown/i, result.warning)
  end
end

require "test_helper"

class SongsIndexTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    @admin = User.create!(church: @church, email: "admin@example.com", password: "secret123", role: "admin")
    post login_path, params: { church_id: @church.id, email: @admin.email, password: "secret123" }
  end

  test "rows show key, the matching lyric line, and when the song was last used in a service" do
    song = @church.songs.create!(title: "Cuán grande es Él", author: "Stuart K. Hine", song_key: "G",
      chordpro_source: "Señor mi [G]Dios\nal contemplar los cielos")
    @church.songs.create!(title: "Sin usar", chordpro_source: "Primera línea")
    [ Date.new(2026, 10, 4), Date.new(2026, 11, 1) ].each do |date|
      set = @church.service_sets.create!(name: date.to_s, service_date: date)
      set.set_items.create!(item_type: "song", song: song, position: 0)
    end

    get songs_path
    assert_select "[data-role=song-row]", count: 2
    assert_select "[data-role=song-row]", text: /Cuán grande es Él/ do
      assert_select ".badge", text: "G"
      assert_select "[data-role=song-snippet]", text: "Señor mi Dios"
      assert_select "td", text: "Nov 1, 2026"
    end
    assert_select "[data-role=song-row]", text: /Sin usar.*Never/m

    get songs_path(q: "contemplar")
    assert_select "[data-role=song-row]", count: 1
    assert_select "[data-role=song-snippet]", text: "al contemplar los cielos"
  end

  test "a search with no matches offers to clear it" do
    @church.songs.create!(title: "Sublime gracia", chordpro_source: "Sublime gracia")
    get songs_path(q: "zzz")
    assert_select "[data-role=song-results] a[href='#{songs_path}']"
    assert_select "[data-role=song-row]", count: 0
  end
end

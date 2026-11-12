require "test_helper"

class SongShowSectionsTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    User.create!(church: @church, email: "ed@example.com", password: "secret123", role: "editor")
    post login_path, params: { church_id: @church.id, email: "ed@example.com", password: "secret123" }
  end

  def labels_in(body)
    body.scan(/data-role="section-label"[^>]*>(.*?)<\/(?:h2|span|div)>/m).flatten.map(&:strip)
  end

  test "arrangement defines order and repeats without hiding unlisted sections" do
    song = @church.songs.create!(
      title: "Ordering",
      chordpro_source: "{sov: Intro}\n[G] [C]\n{sov: Verse 1}\nHola\n{soc: Chorus}\nCoro",
      arrangement: [ "Verse 1", "Chorus", "Verse 1" ]
    )
    get song_path(song)
    assert_response :success
    # arrangement order + repeat first, then the unlisted Intro appended (never dropped)
    assert_equal [ "Verse 1", "Chorus", "Verse 1", "Intro" ], labels_in(response.body)
  end

  test "the details card shows credits, the song flow and the latest service that used the song" do
    song = @church.songs.create!(title: "Detalle", author: "Hine", song_key: "G", ccli_song_number: 14181,
      copyright_line: "© 1953 Hine", arrangement: [ "Verse 1", "Chorus" ],
      chordpro_source: "{key: G}\n{start_of_verse: Verse 1}\n[G]Uno\n{end_of_verse}\n{start_of_chorus: Chorus}\n[C]Dos\n{end_of_chorus}")
    older = @church.service_sets.create!(name: "Octubre", service_date: Date.new(2026, 10, 4))
    newer = @church.service_sets.create!(name: "Noviembre", service_date: Date.new(2026, 11, 1))
    [ older, newer ].each { |set| set.set_items.create!(item_type: "song", song: song, position: 0) }

    get song_path(song)
    assert_select "[data-role=key-badge]", text: "Key G"
    assert_select "dd", text: "14181"
    assert_select "dd", text: "© 1953 Hine"
    assert_select "[data-role=last-used] a[href='#{service_set_path(newer)}']", text: "Noviembre"
    assert_select "[data-role=song-flow] li", count: 2
  end

  test "no arrangement renders sections in natural order" do
    song = @church.songs.create!(
      title: "Natural",
      chordpro_source: "{sov: Intro}\n[G]\n{sov: Verse 1}\nHola",
      arrangement: nil
    )
    get song_path(song)
    assert_response :success
    assert_equal [ "Intro", "Verse 1" ], labels_in(response.body)
  end
end

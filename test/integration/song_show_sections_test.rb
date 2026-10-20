require "test_helper"

class SongShowSectionsTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    User.create!(church: @church, email: "ed@example.com", password: "secret123", role: "editor")
    post login_path, params: { church_id: @church.id, email: "ed@example.com", password: "secret123" }
  end

  def labels_in(body)
    body.scan(/data-role="section-label"[^>]*>(.*?)<\/h2>/m).flatten.map(&:strip)
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

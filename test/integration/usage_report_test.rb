require "test_helper"

class UsageReportTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    @other = Church.create!(name: "Norte")
    User.create!(church: @church, email: "ed@example.com", password: "secret123", role: "editor")

    @song = @church.songs.create!(title: "Cuan grande", author: "Hine", ccli_song_number: 111,
                                  copyright_status: "copyrighted", chordpro_source: "x")
    set = @church.service_sets.create!(name: "S")
    set.set_items.create!(position: 0, item_type: "song", song: @song)

    # Two sessions that both showed the song → two uses.
    @s1 = LiveSession.launch(set)
    @s2 = LiveSession.launch(set)

    # A public-domain song shown → must NOT appear.
    pd = @church.songs.create!(title: "Sublime", copyright_status: "public_domain", chordpro_source: "x")
    UsageEvent.create!(church: @church, live_session: @s1, song: pd, title: "Sublime",
                       copyright_status: "public_domain", shown_at: Time.current)

    # Another church's usage → must be scoped out.
    osong = @other.songs.create!(title: "Ajeno", ccli_song_number: 999, copyright_status: "copyrighted", chordpro_source: "x")
    oset = @other.service_sets.create!(name: "O")
    oset.set_items.create!(position: 0, item_type: "song", song: osong)
    LiveSession.launch(oset)

    post login_path, params: { church_id: @church.id, email: "ed@example.com", password: "secret123" }
  end

  test "the usage CSV reports grouped counts, church-scoped, excluding public-domain" do
    get usage_report_path(from: Date.current.to_s, to: Date.current.to_s)
    assert_response :success
    assert_equal "text/csv", response.media_type

    rows = CSV.parse(response.body)
    assert_equal [ "CCLI Song Number", "Title", "Author", "Times Used" ], rows.first

    data = rows[1..]
    titles = data.map { |r| r[1] }
    assert_includes titles, "Cuan grande"
    assert_not_includes titles, "Sublime", "public-domain excluded"
    assert_not_includes titles, "Ajeno", "other church excluded"

    cuan = data.find { |r| r[1] == "Cuan grande" }
    assert_equal "111", cuan[0]
    assert_equal "2", cuan[3], "two sessions showed the song"
  end
end

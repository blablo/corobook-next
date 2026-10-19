require "test_helper"

class UsageEventTest < ActiveSupport::TestCase
  setup do
    @church = Church.create!(name: "Central")
    @song = @church.songs.create!(title: "Himno", author: "Autor", ccli_song_number: 12345,
                                  copyright_status: "copyrighted", chordpro_source: "[G]x")
    @set = @church.service_sets.create!(name: "Domingo")
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
    @session = LiveSession.launch(@set)
  end

  test "launching captures the opening song exactly once" do
    assert_equal 1, UsageEvent.where(live_session: @session, song: @song).count
  end

  test "capturing the same song again in the same session does not double count" do
    UsageEvent.capture(live_session: @session, song: @song)
    UsageEvent.capture(live_session: @session, song: @song)
    assert_equal 1, UsageEvent.where(live_session: @session, song: @song).count
  end

  test "public-domain songs are not captured" do
    pd = @church.songs.create!(title: "Sublime", copyright_status: "public_domain", chordpro_source: "x")
    UsageEvent.capture(live_session: @session, song: pd)
    assert_equal 0, UsageEvent.where(song: pd).count
  end

  test "the event snapshots song fields and is immune to a later edit" do
    event = UsageEvent.where(live_session: @session, song: @song).first
    assert_equal "Himno", event.title
    assert_equal 12345, event.ccli_song_number

    @song.update!(title: "Renombrado", ccli_song_number: 99999)
    assert_equal "Himno", event.reload.title, "snapshot must not change when the song is edited"
    assert_equal 12345, event.ccli_song_number
  end

  test "a second session of the same set captures its own event" do
    s2 = LiveSession.launch(@set)
    assert_equal 1, UsageEvent.where(live_session: s2, song: @song).count
    assert_equal 2, UsageEvent.where(song: @song).count
  end
end

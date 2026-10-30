require "test_helper"

# The permanent per-service musician link (/m/s/:token) that goes out in the band email.
class ServiceMusicianLinkTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    @song = @church.songs.create!(title: "Himno", song_key: "G", chordpro_source: "{key: G}\n[G]Hola [C]mundo")
    @set = @church.service_sets.create!(name: "Domingo", service_date: Date.new(2026, 11, 1))
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
  end

  test "every service gets a permanent musician token on create" do
    assert @set.musician_token.present?
    assert_not_equal @set.musician_token, @church.service_sets.create!(name: "Otro").musician_token
  end

  test "before going live: the chart renders with a not-live note and no live bar, no sign-in" do
    get service_musician_path(token: @set.musician_token)
    assert_response :success
    assert_select "[data-role=set-name]", text: "Domingo"
    assert_select "[data-role=chart-title]", text: /Himno/
    assert_select "[data-role=not-live]"
    assert_select "[data-role=now-bar]", false
    assert_select "turbo-cable-stream-source", false
  end

  test "while live: the same link follows the live session" do
    session = LiveSession.launch(@set)
    get service_musician_path(token: @set.musician_token)
    assert_response :success
    assert_select "[data-role=now-bar]"
    assert_select "[data-role=not-live]", false
    assert_select "turbo-cable-stream-source"
    assert_select "[data-role=set-row][data-current=true]"
    assert_not_equal session.musician_token, @set.musician_token
  end

  test "after the service ends the link keeps working" do
    LiveSession.launch(@set).end!
    get service_musician_path(token: @set.musician_token)
    assert_response :success
    assert_select "[data-role=not-live]"
  end

  test "transposes to the requested key like the live link" do
    get service_musician_path(token: @set.musician_token, key: "A")
    assert_response :success
    assert_select "[data-role=key-badge]", text: /A/
  end

  test "unknown token is a 404" do
    get service_musician_path(token: "nope")
    assert_response :not_found
  end

  test "the band email links to the permanent musician view" do
    sender = @church.users.create!(email: "ed@example.com", password: "secret123", role: "editor")
    player = @church.users.create!(email: "bass@example.com", password: "secret123", role: "editor", band_member: true)
    text = ServiceSetsMailer.band(@set, player, sender, "en").text_part.body.decoded
    assert_match %r{https?://[^/\s]+/m/s/#{Regexp.escape(@set.musician_token)}}, text
    assert_match %r{/sets/#{@set.id}/preview}, text
  end
end

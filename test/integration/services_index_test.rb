require "test_helper"

class ServicesIndexTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    @admin = User.create!(church: @church, email: "admin@example.com", password: "secret123", role: "admin")
    @song = Song.create!(church: @church, title: "Way Maker", chordpro_source: "{title: Way Maker}\n[C]Way maker")
    post login_path, params: { church_id: @church.id, email: @admin.email, password: "secret123" }
  end

  def service(name, date, songs: 1)
    set = @church.service_sets.create!(name: name, service_date: date)
    songs.times { |i| set.set_items.create!(item_type: "song", song: @song, position: i) }
    set
  end

  test "with no services it shows an empty state with a create action" do
    get service_sets_path
    assert_select "[data-role=empty] a[href='#{new_service_set_path}']"
    assert_select "[data-role=next-service]", count: 0
  end

  test "the nearest upcoming service is the hero and is not repeated in the upcoming list" do
    soon = service("Soon", Date.current + 3)
    later = service("Later", Date.current + 10)
    service("Last week", Date.current - 7)

    get service_sets_path
    assert_select "[data-role=next-service]", text: /Soon/
    assert_select "[data-role=next-service]", text: /in 3 days/
    assert_select "[data-role=next-service] form[action='#{launch_service_set_path(soon)}']"
    assert_select "[data-role=upcoming-sets] [data-role=set-row]", count: 1
    assert_select "[data-role=upcoming-sets]", text: /Later/
    assert_select "[data-role=tab-upcoming] .badge", text: "1"
    assert_select "[data-role=tab-past] .badge", text: "1"
    assert_select "[data-role=past-sets]", count: 0
    assert_select "[data-role=upcoming-sets] form[action='#{launch_service_set_path(later)}']"
  end

  test "with only the next service upcoming, the Upcoming badge matches the empty list" do
    service("Soon", Date.current + 3)
    get service_sets_path
    assert_select "[data-role=next-service]", text: /Soon/
    assert_select "[data-role=tab-upcoming] .badge", text: "0"
    assert_select "[data-role=tab-empty]", text: /No other upcoming services/
  end

  test "the past tab lists past services newest first, a page at a time" do
    service("Soon", Date.current + 3)
    (1..21).each { |n| service("Past #{n}", Date.current - n) }

    get service_sets_path(tab: "past")
    assert_select "[data-role=past-sets] [data-role=set-row]", count: 20
    assert_select "[data-role=past-sets] [data-role=set-row]:first-child", text: /Past 1\b/
    assert_select "[data-role=older-services][href='#{service_sets_path(tab: "past", page: 2)}']"

    get service_sets_path(tab: "past", page: 2)
    assert_select "[data-role=past-sets] [data-role=set-row]", count: 1
    assert_select "[data-role=past-sets]", text: /Past 21/
    assert_select "[data-role=older-services]", count: 0
  end

  test "while a service is live it shows the banner, Resume on that service and no second launch" do
    live = service("Live one", Date.current + 1)
    other = service("Other", Date.current + 8)
    session = LiveSession.launch(live)

    get service_sets_path
    assert_select "[data-role=live-banner] a[href='#{operator_path(session)}']"
    assert_select "[data-role=next-service] [data-role=set-resume][href='#{operator_path(session)}']"
    assert_select "form[action='#{launch_service_set_path(other)}']", count: 0
  end

  test "an empty service offers Add items instead of Go live" do
    service("Soon", Date.current + 3)
    empty = service("Empty", Date.current + 5, songs: 0)

    get service_sets_path
    assert_select "[data-role=upcoming-sets] [data-role=set-add-items][href='#{service_set_path(empty)}']"
    assert_select "form[action='#{launch_service_set_path(empty)}']", count: 0
  end
end

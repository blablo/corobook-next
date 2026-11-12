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

  test "the nearest upcoming service is the hero and also heads the upcoming list, marked Next" do
    soon = service("Soon", Date.current + 3)
    later = service("Later", Date.current + 10)
    service("Last week", Date.current - 7)

    get service_sets_path
    assert_select "[data-role=next-service]", text: /Soon/
    assert_select "[data-role=next-service]", text: /in 3 days/
    assert_select "[data-role=next-service] form[action='#{launch_service_set_path(soon)}']"
    assert_select "[data-role=upcoming-sets] [data-role=set-row]", count: 2
    assert_select "[data-role=upcoming-sets] [data-role=set-row]:first-child", text: /Soon/
    assert_select "[data-role=upcoming-sets] [data-role=set-row]:first-child [data-role=next-badge]"
    assert_select "[data-role=upcoming-sets] [data-role=next-badge]", count: 1
    assert_select "[data-role=upcoming-sets]", text: /Later/
    assert_select "[data-role=tab-upcoming] .badge", text: "2"
    assert_select "[data-role=tab-past] .badge", text: "1"
    assert_select "[data-role=past-sets]", count: 0
    assert_select "[data-role=upcoming-sets] [data-role=set-open][href='#{service_set_path(later)}']"
    assert_select "[data-role=upcoming-sets] form[action='#{launch_service_set_path(later)}']", count: 0
  end

  test "with only the next service upcoming, the Upcoming list still shows it" do
    service("Soon", Date.current + 3)
    get service_sets_path
    assert_select "[data-role=next-service]", text: /Soon/
    assert_select "[data-role=tab-upcoming] .badge", text: "1"
    assert_select "[data-role=upcoming-sets] [data-role=set-row]", count: 1
    assert_select "[data-role=tab-empty]", count: 0
  end

  test "with no upcoming services the Upcoming tab says so" do
    service("Last week", Date.current - 7)
    get service_sets_path
    assert_select "[data-role=tab-upcoming] .badge", text: "0"
    assert_select "[data-role=tab-empty]", text: /No upcoming services/
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
    assert_select "[data-role=upcoming-sets] [data-role=set-row]:first-child [data-role=set-status][data-status=live]"
    assert_select "[data-role=upcoming-sets] [data-role=set-row]:first-child [data-role=set-resume]"
    assert_select "form[action='#{launch_service_set_path(other)}']", count: 0
  end

  test "list rows show the service's status and offer only Open (or Resume)" do
    ready = service("Ready", Date.current + 3)
    empty = service("Empty one", Date.current + 5, songs: 0)

    get service_sets_path
    rows = css_select("[data-role=upcoming-sets] [data-role=set-row]")
    assert_equal [ "ready", "empty" ], rows.map { |r| r.at_css("[data-role=set-status]")["data-status"] }
    assert_equal "Empty", rows.last.at_css("[data-role=set-status]").text.strip
    assert_select "[data-role=upcoming-sets] [data-role=set-open][href='#{service_set_path(empty)}']"
    assert_select "[data-role=upcoming-sets] [data-role=set-open][href='#{service_set_path(ready)}']"
    assert_select "[data-role=upcoming-sets] form", count: 0
  end
end

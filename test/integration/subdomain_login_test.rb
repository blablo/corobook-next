require "test_helper"

class SubdomainLoginTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Gracia", subdomain: "gracia")
    @other  = Church.create!(name: "Central")
    @user   = @church.users.create!(email: "pastor@example.com", password: "secret123", role: "admin")
    # A same-email user in another church, to prove the subdomain pins the right one.
    @other.users.create!(email: "pastor@example.com", password: "secret123", role: "editor")
  end

  test "on a church subdomain the picker is hidden and the church name is shown" do
    get login_url(host: "gracia.example.com")
    assert_response :success
    assert_select "[data-role=subdomain-church]", text: /Gracia/
    assert_select "select[name='church_id']", count: 0
  end

  test "on a church subdomain, login needs only email + password (church pinned)" do
    post login_url(host: "gracia.example.com"),
         params: { email: "pastor@example.com", password: "secret123" }
    assert_redirected_to root_path
    follow_redirect!
    assert_select "[data-role=church-name]", text: "Gracia"
  end

  test "on the bare domain the church picker is shown" do
    get login_url(host: "example.com")
    assert_response :success
    assert_select "select[name='church_id']"
    assert_select "[data-role=subdomain-church]", count: 0
  end

  test "an unknown subdomain falls back to the picker" do
    get login_url(host: "nope.example.com")
    assert_response :success
    assert_select "select[name='church_id']"
  end

  test "www is treated as no subdomain" do
    get login_url(host: "www.example.com")
    assert_response :success
    assert_select "select[name='church_id']"
  end

  # ── Multi-level base host: churches live UNDER a configured base, e.g.
  #    gracia.corobook.duckdns.org where the base host is corobook.duckdns.org. ──
  test "a church under a multi-level base host pins that church" do
    with_app_host("corobook.duckdns.org") do
      get login_url(host: "gracia.corobook.duckdns.org")
      assert_response :success
      assert_select "[data-role=subdomain-church]", text: /Gracia/
      assert_select "select[name='church_id']", count: 0
    end
  end

  test "the bare multi-level base host shows the picker, not a church named for a base label" do
    with_app_host("corobook.duckdns.org") do
      get login_url(host: "corobook.duckdns.org")
      assert_response :success
      assert_select "select[name='church_id']"
      assert_select "[data-role=subdomain-church]", count: 0
    end
  end

  test "a deeper host (a.b.base) is not treated as a church subdomain" do
    with_app_host("corobook.duckdns.org") do
      get login_url(host: "a.gracia.corobook.duckdns.org")
      assert_response :success
      assert_select "select[name='church_id']"
    end
  end

  private

  def with_app_host(host)
    prev = ENV["APP_HOST"]
    ENV["APP_HOST"] = host
    yield
  ensure
    ENV["APP_HOST"] = prev
  end
end

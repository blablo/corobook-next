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
end

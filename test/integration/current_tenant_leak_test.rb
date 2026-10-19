require "test_helper"

class CurrentTenantLeakTest < ActionDispatch::IntegrationTest
  setup do
    @central = Church.create!(name: "Central")
    @norte = Church.create!(name: "Norte")
    @alice = User.create!(church: @central, email: "alice@example.com", password: "secret123", role: "admin")
    @bob = User.create!(church: @norte, email: "bob@example.com", password: "secret123", role: "editor")
  end

  # Current is request-local: a second request by a different-church user must not see the
  # first request's Current.church (design §3.2.2).
  test "Current.church does not leak between sequential requests" do
    post login_path, params: { church_id: @central.id, email: @alice.email, password: "secret123" }
    get login_path
    assert_match @central.name, response.body

    post login_path, params: { church_id: @norte.id, email: @bob.email, password: "secret123" }
    get login_path
    assert_match @norte.name, response.body
    assert_no_match @central.name, response.body
  end

  test "an unauthenticated request leaves Current unset" do
    get login_path
    assert_select "[data-role=signed-in]", false
  end
end

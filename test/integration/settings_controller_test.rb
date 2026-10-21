require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Gracia")
    @admin = @church.users.create!(email: "admin@example.com", password: "secret123", role: "admin")
    @editor = @church.users.create!(email: "ed@example.com", password: "secret123", role: "editor")
  end

  def login(user)
    post login_path, params: { church_id: @church.id, email: user.email, password: "secret123" }
  end

  test "an admin sees the settings page with the subdomain field" do
    login(@admin)
    get settings_path
    assert_response :success
    assert_select "[data-role=settings]"
    assert_select "[data-role=subdomain-input]"
  end

  test "an admin can set the subdomain" do
    login(@admin)
    patch settings_path, params: { church: { subdomain: "Gracia" } }
    assert_redirected_to settings_path
    assert_equal "gracia", @church.reload.subdomain
  end

  test "an invalid subdomain re-renders with an error" do
    login(@admin)
    patch settings_path, params: { church: { subdomain: "www" } }
    assert_response :unprocessable_entity
    assert_select "[data-role=subdomain-error]"
    assert_nil @church.reload.subdomain
  end

  test "an editor is denied the settings page" do
    login(@editor)
    get settings_path
    assert_redirected_to login_path
  end

  test "the admin sidebar links to settings" do
    login(@admin)
    get root_path
    assert_select "[data-role=nav-settings]"
  end
end

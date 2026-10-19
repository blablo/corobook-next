require "test_helper"

class HomePageTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Iglesia Central")
    @user = User.create!(church: @church, email: "home@example.com", password: "secret123", role: "admin")
  end

  test "a signed-out visitor to root is redirected to login" do
    get root_path
    assert_redirected_to login_path
  end

  test "a signed-in user sees the home page with their church name" do
    sign_in
    get root_path
    assert_response :success
    assert_select "[data-role=home]", /Iglesia Central/
  end

  test "signing in lands on the home page, not back on login" do
    post login_path, params: { church_id: @church.id, email: @user.email, password: "secret123" }
    assert_redirected_to root_path
  end

  private

  def sign_in
    post login_path, params: { church_id: @church.id, email: @user.email, password: "secret123" }
  end
end

require "test_helper"

class RegistrationsTest < ActionDispatch::IntegrationTest
  test "signed-out root shows the public landing page, not a login redirect" do
    get root_path
    assert_response :success
    assert_select "[data-role=landing]"
    assert_select "[data-role=cta-signup]"
  end

  test "signed-in root shows the dashboard" do
    church = Church.create!(name: "Gracia")
    user = church.users.create!(email: "a@example.com", password: "secret123", role: "admin")
    post login_path, params: { church_id: church.id, email: user.email, password: "secret123" }
    get root_path
    assert_response :success
    assert_select "[data-role=home]"
    assert_select "[data-role=landing]", count: 0
  end

  test "the signup page renders" do
    get signup_path
    assert_response :success
    assert_select "[data-role=signup]"
    assert_select "[data-role=church-name]"
    assert_select "[data-role=admin-email]"
  end

  test "signup creates a church and its first admin, then signs in" do
    assert_difference [ "Church.count", "User.count" ], 1 do
      post signup_path, params: {
        church: { name: "Nueva Vida", subdomain: "nueva-vida" },
        user: { email: "pastor@example.com", password: "secret123", password_confirmation: "secret123" }
      }
    end
    assert_redirected_to root_path
    church = Church.find_by(name: "Nueva Vida")
    assert_equal "nueva-vida", church.subdomain
    user = church.users.sole
    assert user.admin?
    assert_equal "pastor@example.com", user.email
    # Signed in — root now shows the dashboard.
    follow_redirect!
    assert_select "[data-role=home]"
  end

  test "signup is atomic: a bad subdomain rolls back the church too" do
    assert_no_difference [ "Church.count", "User.count" ] do
      post signup_path, params: {
        church: { name: "Bad", subdomain: "www" }, # reserved
        user: { email: "x@example.com", password: "secret123", password_confirmation: "secret123" }
      }
    end
    assert_response :unprocessable_entity
    assert_select "[data-role=signup-error]"
  end

  test "signup rejects mismatched passwords" do
    assert_no_difference "Church.count" do
      post signup_path, params: {
        church: { name: "Mismatch" },
        user: { email: "x@example.com", password: "secret123", password_confirmation: "nope12345" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "a signed-in user is redirected away from signup" do
    church = Church.create!(name: "Gracia")
    user = church.users.create!(email: "a@example.com", password: "secret123", role: "admin")
    post login_path, params: { church_id: church.id, email: user.email, password: "secret123" }
    get signup_path
    assert_redirected_to root_path
  end
end

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

  test "the admin sidebar nests General and Projection under Settings" do
    login(@admin)
    get root_path
    assert_select "[data-role=nav-settings]"
    assert_select "[data-role=nav-settings-general]"
    assert_select "[data-role=nav-settings-projection]"
  end

  test "the general settings page shows the subdomain, not the projection form" do
    login(@admin)
    get settings_path
    assert_response :success
    assert_select "[data-role=subdomain-input]"
    assert_select "[data-role=projector-settings]", false
  end

  test "an admin sees the projection sub-page with a live preview" do
    login(@admin)
    get projection_settings_path
    assert_response :success
    assert_select "[data-role=projector-settings]"
    assert_select "[data-role=pp-stage]"
    assert_select "[data-role=pp-pagination]"
  end

  test "an editor is denied the projection sub-page" do
    login(@editor)
    get projection_settings_path
    assert_redirected_to login_path
  end

  test "saving projection settings redirects back to the projection sub-page" do
    login(@admin)
    patch settings_path, params: { section: "projection", church: {
      projector_bg_color: "#112233", projector_text_color: "#eeeeee",
      projector_bg_type: "gradient", projector_bg_color2: "#334455", projector_bg_gradient_angle: "120",
      projector_font: "serif", projector_lyric_case: "upper",
      projector_valign: "top", projector_pagination: "by_lines",
      projector_lines_per_slide: "6", projector_bold: "0", projector_show_credits: "0"
    } }
    assert_redirected_to projection_settings_path
    @church.reload
    assert_equal "#112233", @church.projector_bg_color
    assert_equal "gradient", @church.projector_bg_type
    assert_equal "#334455", @church.projector_bg_color2
    assert_equal 120, @church.projector_bg_gradient_angle
    assert_equal "serif", @church.projector_font
    assert_equal "upper", @church.projector_lyric_case
    assert_equal "top", @church.projector_valign
    assert_equal "by_lines", @church.projector_pagination
    assert_equal 6, @church.projector_lines_per_slide
    refute @church.projector_bold
    refute @church.projector_show_credits
  end

  test "invalid projection settings re-render the projection page unprocessable" do
    login(@admin)
    patch settings_path, params: { section: "projection", church: { projector_bg_color: "notacolor" } }
    assert_response :unprocessable_entity
    assert_select "[data-role=projector-settings]"
    assert_equal "#000000", @church.reload.projector_bg_color
  end

  test "saving general settings redirects back to the general page" do
    login(@admin)
    patch settings_path, params: { section: "general", church: { subdomain: "gracia" } }
    assert_redirected_to settings_path
    assert_equal "gracia", @church.reload.subdomain
  end
end

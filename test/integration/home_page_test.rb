require "test_helper"

class HomePageTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Iglesia Central")
    @user = User.create!(church: @church, email: "home@example.com", password: "secret123", role: "admin")
  end

  test "a signed-out visitor to root sees the public landing page" do
    get root_path
    assert_response :success
    assert_select "[data-role=landing]"
    assert_select "[data-role=cta-signup]"
  end

  test "a signed-in user sees the home page with their church name" do
    sign_in
    get root_path
    assert_response :success
    assert_select "[data-role=home]"
    assert_select "[data-role=church-name]", /Iglesia Central/
  end

  test "signing in lands on the home page, not back on login" do
    post login_path, params: { church_id: @church.id, email: @user.email, password: "secret123" }
    assert_redirected_to root_path
  end

  test "an admin sees the usage-report nav entry" do
    sign_in
    get root_path
    assert_select "[data-role=nav-usage]"
  end

  test "an editor does not see the usage-report nav entry" do
    editor = User.create!(church: @church, email: "ed@example.com", password: "secret123", role: "editor")
    post login_path, params: { church_id: @church.id, email: editor.email, password: "secret123" }
    get root_path
    assert_select "[data-role=nav-usage]", false
  end

  test "library counts reflect church data and exclude inline slides and other churches" do
    @church.songs.create!(title: "A", chordpro_source: "x")
    @church.songs.create!(title: "B", chordpro_source: "y")
    @church.text_slides.create!(title: "Reusable", reusable: true)
    set = @church.service_sets.create!(name: "S")
    @church.text_slides.create!(title: "Inline", reusable: false, set_id: set.id) # excluded from count
    other = Church.create!(name: "Norte")
    other.songs.create!(title: "Foreign", chordpro_source: "z") # must not leak into counts

    sign_in
    get root_path
    assert_select "[data-role=library-stats]" do
      assert_select ".text-3xl", text: "2"  # songs (church-scoped, not 3)
      assert_select ".text-3xl", text: "1"  # reusable slides only (not 2)
    end
  end

  private

  def sign_in
    post login_path, params: { church_id: @church.id, email: @user.email, password: "secret123" }
  end
end

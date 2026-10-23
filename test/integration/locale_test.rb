require "test_helper"

class LocaleTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    @user = @church.users.create!(email: "u@example.com", password: "secret123", role: "editor")
  end

  def login
    post login_path, params: { church_id: @church.id, email: @user.email, password: "secret123" }
  end

  test "defaults to English with no hints" do
    login
    get root_path
    assert_select "[data-role=sidebar]", text: /Songs/
  end

  test "an es Accept-Language defaults a user with no saved locale to Spanish" do
    login
    get root_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "es-MX,es;q=0.9" }
    assert_select "[data-role=sidebar]", text: /Canciones/
  end

  test "?locale=es switches and persists for the signed-in user" do
    login
    get root_path(locale: :es)
    assert_select "[data-role=sidebar]", text: /Canciones/
    assert_equal "es", @user.reload.locale
  end

  test "a saved locale wins over the browser hint" do
    @user.update!(locale: "en")
    login
    get root_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "es-MX,es;q=0.9" }
    assert_select "[data-role=sidebar]", text: /Songs/
  end

  test "an unsupported locale param is ignored" do
    login
    get root_path(locale: "fr")
    assert_select "[data-role=sidebar]", text: /Songs/
    assert_nil @user.reload.locale
  end
end

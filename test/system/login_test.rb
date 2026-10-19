require "application_system_test_case"

class LoginTest < ApplicationSystemTestCase
  setup do
    @central = Church.create!(name: "Central")
    @norte = Church.create!(name: "Norte")
    User.create!(church: @central, email: "pastor@example.com", password: "secret123", role: "admin")
    User.create!(church: @norte, email: "pastor@example.com", password: "secret123", role: "editor")
  end

  test "same email logs into the chosen church" do
    visit login_path
    select "Norte", from: "Church"
    fill_in "Email", with: "pastor@example.com"
    fill_in "Password", with: "secret123"
    click_on "Sign in"

    # Lands on the home launchpad for the chosen church (church name shown in the shell header).
    assert_text "Signed in to Norte"              # flash notice
    assert_selector "[data-role=home]"            # landed on the home page
    assert_selector "[data-role=church-name]", text: "Norte"
    assert_text "pastor@example.com"
  end

  test "wrong password is rejected" do
    visit login_path
    select "Central", from: "Church"
    fill_in "Email", with: "pastor@example.com"
    fill_in "Password", with: "nope"
    click_on "Sign in"

    assert_text "Invalid church, email, or password."
  end
end

require "application_system_test_case"

class HomeLaunchpadTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Iglesia Central")
    @user = User.create!(church: @church, email: "home@example.com", password: "secret123", role: "admin")
    @song = @church.songs.create!(title: "Himno", chordpro_source: "[G]Hola")
    @set = @church.service_sets.create!(name: "Domingo AM", service_date: Date.current + 1)
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
    visit login_path
    select @church.name, from: "Church"
    fill_in "Email", with: @user.email
    fill_in "Password", with: "secret123"
    click_on "Sign in"
    assert_selector "[data-role=home]"
  end

  test "the hero shows the next set and Go Live launches the operator" do
    within "[data-role=hero]" do
      assert_text "Domingo AM"
      assert_text(/next service/i)
    end
    find("[data-role=go-live]").click
    assert_current_path(/\/operator\/\d+/)
  end

  test "with an active session the hero shows Resume and no Go Live" do
    LiveSession.launch(@set)
    visit root_path
    assert_selector "[data-role=resume]"
    assert_no_selector "[data-role=go-live]"
  end
end

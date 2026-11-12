require "application_system_test_case"

class ServiceTemplatesSystemTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central")
    @editor = User.create!(church: @church, email: "editor@example.com", password: "secret123", role: "editor")
    @church.songs.create!(title: "Himno de apertura", song_key: "G", chordpro_source: "[G]Hola")
    @church.text_slides.create!(title: "Salmo 23", reusable: true, tags: [ "scripture" ],
                                pages: [ { "body_markdown" => "El Señor es mi pastor" } ])
    @template = @church.service_sets.create!(name: "Domingo base", template: true)
    sign_in @editor
  end

  def sign_in(user)
    visit login_path
    select @church.name, from: "Church"
    fill_in "Email", with: user.email
    fill_in "Password", with: "secret123"
    click_on "Sign in"
    assert_selector "[data-role=home]"
  end

  test "build a template with slots, start a service from it, fill a slot and go live" do
    visit service_set_path(@template)
    find("[data-role=tab-slots]").click
    fill_in "slot-label", with: "Worship song"
    click_on "+ Song slot"
    assert_selector "[data-role=set-item]", text: "Worship song"
    within("[data-role=slot-tags]") { click_on "scripture" }
    assert_selector "[data-role=set-item]", count: 2
    assert_selector "[data-role=set-item]", text: "Scripture"

    visit new_service_set_path(from_template_id: @template.id)
    click_on "Create service"
    assert_selector "[data-role=slots-to-fill]", text: "2 slots to fill"

    find("[data-role=choose-slot][data-slot-kind=slide]").click
    within("dialog[open]") do
      assert_text "Showing slides tagged scripture"
      within("[data-role=slot-result]", text: "Salmo 23") { click_on "Use" }
    end
    assert_no_selector "dialog[open]"
    assert_selector "[data-role=set-item]", text: "Salmo 23"
    assert_selector "[data-role=slots-to-fill]", text: "1 slot to fill"

    find("[data-role=launch]").click
    within("dialog[open]") do
      assert_text "1 slot is still empty"
      click_on "Go live anyway"
    end
    assert_current_path(/\/operator\/\d+/)
  end
end

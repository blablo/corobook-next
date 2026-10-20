require "application_system_test_case"

class SetBuilderTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central")
    @editor = User.create!(church: @church, email: "editor@example.com", password: "secret123", role: "editor")
    @song = @church.songs.create!(title: "Himno de apertura", song_key: "G", chordpro_source: "[G]Hola")
    @set = @church.service_sets.create!(name: "Domingo AM")
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

  test "build a mixed set via search + inline slide, reorder, and persist" do
    visit service_set_path(@set)

    # Add the song via the search picker.
    fill_in "set-builder-search", with: "Himno"
    find(".result", text: "Himno de apertura").click
    assert_selector "[data-role=set-item]", text: "Himno de apertura"

    # Add an inline one-off sermon slide via the "New slide" tab.
    click_on "New slide"
    fill_in "inline-title", with: "Punto 1"
    fill_in "inline-body", with: "**Dios es fiel**"
    click_on "Add slide"
    assert_selector "[data-role=set-item]", text: "Punto 1"

    items = all("[data-role=set-item]").map(&:text)
    assert_equal 2, items.length
    assert_match "Himno de apertura", items[0]

    # Move the slide up with the ↑ arrow.
    within all("[data-role=set-item]").last do
      click_on "↑"
    end
    assert_match "Punto 1", all("[data-role=set-item]").first.text

    # Persisted across reload.
    visit service_set_path(@set)
    assert_match "Punto 1", all("[data-role=set-item]").first.text

    inline = @church.text_slides.find_by(title: "Punto 1")
    assert_not inline.reusable
    assert_equal @set.id, inline.set_id
  end

  test "blank inline-slide title shows an error and adds nothing" do
    visit service_set_path(@set)
    click_on "New slide"
    fill_in "inline-body", with: "no title"
    click_on "Add slide"
    assert_selector "[data-set-builder-target=inlineError]", visible: true
    assert_no_selector "[data-role=set-item]"
  end

  test "removing an item updates the list without reload" do
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
    visit service_set_path(@set)
    assert_selector "[data-role=set-item]", count: 1
    within all("[data-role=set-item]").first do
      click_on "✕"
    end
    assert_no_selector "[data-role=set-item]"
  end

  test "setting the service date inline persists it" do
    visit service_set_path(@set)
    input = find("[data-role=service-date]")
    # Native date inputs are unreliable with fill_in under Selenium; set value + fire change.
    page.execute_script("arguments[0].value = '2026-12-25'; arguments[0].dispatchEvent(new Event('change'))", input.native)
    assert_text "goes live"
    assert_equal Date.new(2026, 12, 25), @set.reload.service_date
  end
end

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

  test "build a mixed set via search + new-slide modal, reorder, and persist" do
    visit service_set_path(@set)

    # Add the song via the search picker.
    fill_in "set-builder-search", with: "Himno"
    find(".result", text: "Himno de apertura").click
    assert_selector "[data-role=set-item]", text: "Himno de apertura"

    # Add a slide via the full "New slide" modal (same editor as /text_slides/new).
    find("[role=tab]", text: "Slides").click
    click_on "+ New slide"
    assert_selector "dialog[open]"
    within("dialog[open]") do
      fill_in "Slide title", with: "Punto 1"
      # Type into the WYSIWYG body (query the live node by selector; no stale handle across JS).
      page.execute_script(<<~JS)
        const el = document.querySelector("dialog[open] [data-slide-editor-target=rich]")
        el.focus(); el.textContent = "Dios es fiel"
        el.dispatchEvent(new Event("input", { bubbles: true }))
      JS
      click_on "Create slide"
    end
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

    # Modal slides are saved to the library (reusable) AND added to this set.
    slide = @church.text_slides.find_by(title: "Punto 1")
    assert slide.reusable
    assert @set.set_items.exists?(text_slide_id: slide.id)
  end

  test "blank slide title in the modal shows a validation error and adds nothing" do
    visit service_set_path(@set)
    find("[role=tab]", text: "Slides").click
    click_on "+ New slide"
    assert_selector "dialog[open]"
    within("dialog[open]") do
      page.execute_script(<<~JS)
        const el = document.querySelector("dialog[open] [data-slide-editor-target=rich]")
        el.focus(); el.textContent = "no title"
        el.dispatchEvent(new Event("input", { bubbles: true }))
      JS
      click_on "Create slide"
    end
    # Validation fails (title required) → modal stays, no item added.
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

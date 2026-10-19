require "application_system_test_case"

class SetBuilderTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central")
    @editor = User.create!(church: @church, email: "editor@example.com", password: "secret123", role: "editor")
    @song = @church.songs.create!(title: "Himno de apertura", chordpro_source: "[G]Hola")
    @set = @church.service_sets.create!(name: "Domingo AM")
    visit login_path
    select @church.name, from: "Church"
    fill_in "Email", with: @editor.email
    fill_in "Password", with: "secret123"
    click_on "Sign in"
    assert_selector "[data-role=home]" # landed on home after login
  end

  test "build a mixed set with a song and an inline sermon slide, then reorder" do
    visit service_set_path(@set)

    # Add the song.
    within(:xpath, "//section[h2[contains(., 'Add a song')]]") do
      select "Himno de apertura", from: "song_id"
      click_on "Add song"
    end
    assert_selector "[data-role=set-item]", text: "Himno de apertura"

    # Add an inline one-off sermon slide.
    within(:xpath, "//section[h2[contains(., 'inline one-off slide')]]") do
      fill_in "title", with: "Punto 1"
      fill_in "body_markdown", with: "**Dios es fiel**"
      click_on "Add inline slide"
    end
    assert_selector "[data-role=set-item]", text: "Punto 1"

    # Two items, song first.
    items = all("[data-role=set-item]").map(&:text)
    assert_equal 2, items.length
    assert_match "Himno de apertura", items[0]

    # Move the sermon slide up.
    within all("[data-role=set-item]").last do
      click_on "↑"
    end
    assert_match "Punto 1", all("[data-role=set-item]").first.text

    # Persisted: reopening shows the slide first.
    visit service_set_path(@set)
    assert_match "Punto 1", all("[data-role=set-item]").first.text

    # The inline slide is set-owned (reusable=false) and not in the reusable library.
    inline = @church.text_slides.find_by(title: "Punto 1")
    assert_not inline.reusable
    assert_equal @set.id, inline.set_id
  end
end

require "application_system_test_case"

class TextSlideEditorTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central")
    @editor = User.create!(church: @church, email: "editor@example.com", password: "secret123", role: "editor")
    visit login_path
    select @church.name, from: "Church"
    fill_in "Email", with: @editor.email
    fill_in "Password", with: "secret123"
    click_on "Sign in"
    assert_selector "[data-role=home]" # landed on home after login
  end

  test "create a tagged, two-page slide with the WYSIWYG editor" do
    visit new_text_slide_path
    fill_in "Title", with: "El Credo"

    # Tags: type + Enter creates a chip.
    find("[data-slide-editor-target=tagInput]").set("scripture")
    find("[data-slide-editor-target=tagInput]").send_keys(:enter)
    find("[data-slide-editor-target=tagInput]").set("advent")
    find("[data-slide-editor-target=tagInput]").send_keys(:enter)
    assert_selector "[data-slide-editor-target=tagChips]", text: "scripture"
    assert_selector "[data-slide-editor-target=tagChips]", text: "advent"

    # Page 1: type and bold a word via the toolbar (no markdown shown).
    find("[data-slide-editor-target=rich]").click
    find("[data-slide-editor-target=rich]").send_keys("Creo en un solo Dios")
    page.execute_script(<<~JS)
      const el = document.querySelector("[data-slide-editor-target=rich]")
      const n = document.createTreeWalker(el, NodeFilter.SHOW_TEXT).nextNode()
      const r = document.createRange(); r.setStart(n, 0); r.setEnd(n, 4)
      const s = window.getSelection(); s.removeAllRanges(); s.addRange(r)
    JS
    find("[data-slide-editor-target=toolbar]").click_button("B")

    # Add a second page and type its body.
    click_on "+ page"
    assert_selector "[data-slide-editor-target=pageLabel]", text: "Page 2 of 2"
    find("[data-slide-editor-target=rich]").click
    find("[data-slide-editor-target=rich]").send_keys("y en su Hijo Jesucristo")

    click_on "Create slide"
    assert_text "Slide created."

    slide = @church.text_slides.find_by(title: "El Credo")
    assert_equal %w[scripture advent].sort, slide.tags.sort
    assert_equal 2, slide.page_count
    assert_includes slide.page_markdown(0), "**Creo**"
    assert_includes slide.page_markdown(1), "Jesucristo"
  end

  test "slides are searchable and filterable by tag" do
    @church.text_slides.create!(title: "Salmo 23", tags: [ "scripture" ], pages: [ { "body_markdown" => "Jehová" } ], reusable: true)
    @church.text_slides.create!(title: "Aviso", tags: [ "announcement" ], pages: [ { "body_markdown" => "Reunión" } ], reusable: true)

    visit text_slides_path
    # Filter by the scripture tag.
    within "[data-role=tag-filter]" do
      click_on "scripture"
    end
    assert_text "Salmo 23"
    assert_no_text "Aviso"
  end

  test "the library shows a page-count badge for a multi-page slide" do
    @church.text_slides.create!(title: "Largo", tags: [], reusable: true,
      pages: [ { "body_markdown" => "uno" }, { "body_markdown" => "dos" } ])
    visit text_slides_path
    assert_selector "li", text: "Largo"
    assert_selector "li", text: "2 pages"
  end
end

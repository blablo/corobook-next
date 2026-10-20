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

  test "creating a statement-of-faith slide renders it with subtype styling" do
    visit new_text_slide_path
    fill_in "Title", with: "El Credo"
    select "Statement of faith", from: "Type"

    # WYSIWYG body: type into the contenteditable, then bold a word via the toolbar.
    rich = find("[data-slide-editor-target=rich]")
    rich.click
    rich.send_keys("Creo en un solo Dios")
    # Select the first word ("Creo") and bold it, finding the first text node robustly.
    page.execute_script(<<~JS, rich.native)
      const el = arguments[0]
      const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT)
      const textNode = walker.nextNode()
      const r = document.createRange()
      r.setStart(textNode, 0); r.setEnd(textNode, 4)
      const s = window.getSelection(); s.removeAllRanges(); s.addRange(r)
    JS
    find("[data-slide-editor-target=toolbar]").click_button("B")

    # The hidden markdown field now carries generated markdown (no syntax typed by the user).
    assert_equal "**Creo** en un solo Dios", find("[data-slide-editor-target=source]", visible: false).value

    # Live preview reflects the formatting + subtype before saving.
    assert_selector "[data-role=slide-preview].slide-statement-of-faith strong", text: "Creo"

    click_on "Create slide"

    assert_text "Slide created."

    within "[data-role=projector-preview]" do
      assert_selector ".slide-statement-of-faith[data-subtype=statement_of_faith]"
      assert_selector "strong", text: "Creo"
    end
    within "[data-role=musician-preview]" do
      assert_selector ".slide-statement-of-faith"
    end
  end
end

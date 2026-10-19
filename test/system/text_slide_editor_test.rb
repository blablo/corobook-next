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
    fill_in "Body (markdown)", with: "**Creo** en un solo Dios"
    click_on "Create Text slide"

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

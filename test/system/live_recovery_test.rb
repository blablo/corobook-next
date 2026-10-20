require "application_system_test_case"

class LiveRecoveryTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central")
    @editor = User.create!(church: @church, email: "op@example.com", password: "secret123", role: "editor")
    @song = @church.songs.create!(title: "Tres",
      chordpro_source: "{sov: V1}\nUno\n{eov}\n{sov: V2}\nDos\n{eov}\n{soc}\nCoro\n{eoc}")
    @set = @church.service_sets.create!(name: "Domingo")
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
    @session = LiveSession.launch(@set)
    visit login_path
    select @church.name, from: "Church"
    fill_in "Email", with: @editor.email
    fill_in "Password", with: "secret123"
    click_on "Sign in"
    assert_selector "[data-role=home]" # landed on home after login
  end

  test "a projector joining mid-service lands on the current section" do
    # Section 0 = title, 1 = V1 (Uno), 2 = V2 (Dos). Advance to V2 before the projector connects.
    @session.update!(current_section_index: 2, position_version: 2)

    visit projector_path(@session.projector_token)
    assert_text "Dos"
    assert_no_text "Uno"
  end

  test "an operator reload lands on the current position" do
    visit operator_path(@session)
    click_on "Next →" # title -> V1 (Uno)
    click_on "Next →" # V1 -> V2 (Dos)
    assert_text "Dos"

    # Cold reload — reads the LiveSession row and lands where we were.
    visit operator_path(@session)
    assert_text "Dos"
    assert_no_text "Uno"
  end
end

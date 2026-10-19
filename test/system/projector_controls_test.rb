require "application_system_test_case"

class ProjectorControlsTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central")
    @editor = User.create!(church: @church, email: "op@example.com", password: "secret123", role: "editor")
    @song = @church.songs.create!(title: "Himno", chordpro_source: "Gloria a Dios")
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

  test "blanking blacks the projector" do
    visit operator_path(@session)
    click_on "Blank"
    assert_selector "[data-role=blank-toggle]", text: "Unblank" # wait for the redirect to settle
    assert @session.reload.blanked

    visit projector_path(@session.projector_token)
    assert_selector "[data-role=blank]"
    assert_no_selector "[data-role=projector-lyrics]"
  end

  test "font plus and minus change the scale" do
    visit operator_path(@session)
    assert_text "100%"
    click_on "A+"
    assert_text "110%"
    assert_equal 110, @session.reload.font_scale

    visit projector_path(@session.projector_token)
    assert_equal "110", find("[data-role=projector-frame]")["data-font-scale"]
  end
end

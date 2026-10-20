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

  test "a clicker / keyboard arrows advance and go back" do
    # A second, multi-section song so there are several advance stops to move through.
    multi = @church.songs.create!(title: "Dos", chordpro_source: "{sov: Verse 1}\nUno\n{soc: Chorus}\nDos")
    @set.set_items.create!(position: 1, item_type: "song", song: multi)

    pos = -> { s = @session.reload; [ s.current_set_item_id, s.current_section_index ] }

    visit operator_path(@session)
    start = pos.call

    # Right arrow (what most presentation clickers send to advance).
    find("body").send_keys(:right)
    assert_selector "[data-role=operator-frame]"
    assert_not_equal start, pos.call, "expected Right arrow to advance the session"

    # Left arrow goes back to where we started.
    find("body").send_keys(:left)
    assert_selector "[data-role=operator-frame]"
    assert_equal start, pos.call, "expected Left arrow to go back"
  end

  test "a clicker / keyboard on the projector page itself advances and goes back" do
    multi = @church.songs.create!(title: "Dos", chordpro_source: "{sov: Verse 1}\nUno\n{soc: Chorus}\nDos")
    @set.set_items.create!(position: 1, item_type: "song", song: multi)
    pos = -> { s = @session.reload; [ s.current_set_item_id, s.current_section_index ] }

    # No sign-in: the projector page is reached by token alone.
    visit projector_path(@session.projector_token)
    assert_selector "[data-role=projector-root]"
    start = pos.call

    find("body").send_keys(:right)
    assert_selector "[data-role=projector-root]"
    assert_not_equal start, pos.call, "expected Right arrow on the projector page to advance"

    find("body").send_keys(:left)
    assert_equal start, pos.call, "expected Left arrow on the projector page to go back"
  end
end

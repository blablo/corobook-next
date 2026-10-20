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

  # Wait for the async key -> POST -> broadcast round-trip to land the expected position.
  def assert_position(expected, msg)
    ok = false
    20.times do
      s = @session.reload
      if [ s.current_set_item_id, s.current_section_index ] == expected
        ok = true
        break
      end
      sleep 0.1
    end
    assert ok, "#{msg} (position was #{[ @session.current_set_item_id, @session.current_section_index ].inspect})"
  end

  test "a clicker / keyboard arrows advance and go back" do
    multi = @church.songs.create!(title: "Dos", chordpro_source: "{sov: Verse 1}\nUno\n{soc: Chorus}\nDos")
    @set.set_items.create!(position: 1, item_type: "song", song: multi)

    visit operator_path(@session)
    s = @session.reload
    start = [ s.current_set_item_id, s.current_section_index ]

    # Right arrow advances; wait for the position to actually change.
    find("body").send_keys(:right)
    advanced = nil
    20.times { advanced = ([ @session.reload.current_set_item_id, @session.current_section_index ] != start) ? true : nil; break if advanced; sleep 0.1 }
    assert advanced, "expected Right arrow to advance the session"

    # Left arrow returns to the start.
    find("body").send_keys(:left)
    assert_position start, "expected Left arrow to go back"
  end

  test "a clicker / keyboard on the projector page itself advances and goes back" do
    multi = @church.songs.create!(title: "Dos", chordpro_source: "{sov: Verse 1}\nUno\n{soc: Chorus}\nDos")
    @set.set_items.create!(position: 1, item_type: "song", song: multi)

    # No sign-in: the projector page is reached by token alone.
    visit projector_path(@session.projector_token)
    assert_selector "[data-role=projector-root]"
    s = @session.reload
    start = [ s.current_set_item_id, s.current_section_index ]

    find("body").send_keys(:right)
    advanced = nil
    20.times { advanced = ([ @session.reload.current_set_item_id, @session.current_section_index ] != start) ? true : nil; break if advanced; sleep 0.1 }
    assert advanced, "expected Right arrow on the projector page to advance"

    find("body").send_keys(:left)
    assert_position start, "expected Left arrow on the projector page to go back"
  end
end

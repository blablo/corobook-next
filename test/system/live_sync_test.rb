require "application_system_test_case"

class LiveSyncTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central")
    @editor = User.create!(church: @church, email: "op@example.com", password: "secret123", role: "editor")
    @song = @church.songs.create!(title: "Tres secciones",
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

  test "advancing moves the operator frame forward through sections" do
    visit operator_path(@session)
    within("[data-role=operator-frame]") { assert_text "Uno" }
    click_on "Next →"
    within("[data-role=operator-frame]") { assert_text "Dos" }
    click_on "Next →"
    within("[data-role=operator-frame]") { assert_text "Coro" }
    # Going back never lands past where we are.
    click_on "← Back"
    within "[data-role=operator-frame]" do
      assert_text "Dos"
      assert_no_text "Coro"
    end
  end

  test "the projector view carries a monotonic position version on its frame" do
    visit projector_path(@session.projector_token)
    frame = find("[data-role=projector-frame]")
    v0 = frame["data-follower-version-value"].to_i

    # Operator advances; the row's version increases.
    Corobook::LivePosition.new(@set).then do
      @session.update!(current_section_index: 1, position_version: @session.position_version + 1)
    end
    visit projector_path(@session.projector_token)
    v1 = find("[data-role=projector-frame]")["data-follower-version-value"].to_i
    assert v1 > v0, "version must increase as the service advances"
  end
end

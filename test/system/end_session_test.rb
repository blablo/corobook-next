require "application_system_test_case"

class EndSessionTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central")
    @editor = User.create!(church: @church, email: "op@example.com", password: "secret123", role: "editor")
    @song = @church.songs.create!(title: "Himno", chordpro_source: "Gloria")
    @set = @church.service_sets.create!(name: "Domingo")
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
    @session = LiveSession.launch(@set)
    @projector_token = @session.projector_token
    @musician_token = @session.musician_token
    visit login_path
    select @church.name, from: "Church"
    fill_in "Email", with: @editor.email
    fill_in "Password", with: "secret123"
    click_on "Sign in"
    assert_selector "[data-role=home]" # landed on home after login
  end

  test "ending the service revokes both tokens and the followers can no longer connect" do
    visit operator_path(@session)
    click_on "End service"
    assert_text "Service ended."

    @session.reload
    assert @session.ended?
    assert_nil @session.projector_token
    assert_nil @session.musician_token

    # The previously-valid tokens now 404.
    visit projector_path(@projector_token)
    assert_text "The page you were looking for doesn't exist"
  end
end

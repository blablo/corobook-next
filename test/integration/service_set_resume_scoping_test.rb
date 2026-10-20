require "test_helper"

class ServiceSetResumeScopingTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    User.create!(church: @church, email: "op@example.com", password: "secret123", role: "editor")
    @song = @church.songs.create!(title: "A", chordpro_source: "[C]x")
    post login_path, params: { church_id: @church.id, email: "op@example.com", password: "secret123" }
  end

  test "a set resumes only its OWN active session, not another set's" do
    other = @church.service_sets.create!(name: "Other")
    other.set_items.create!(position: 0, item_type: "song", song: @song)
    session = LiveSession.launch(other) # the church's single active session, owned by `other`

    mine = @church.service_sets.create!(name: "Mine")
    mine.set_items.create!(position: 0, item_type: "song", song: @song)

    # `mine` must NOT present a Resume link pointing at another set's operator session.
    get service_set_path(mine)
    assert_response :success
    assert_not_includes response.body, operator_path(session)

    # The owning set does present its own Resume link.
    get service_set_path(other)
    assert_includes response.body, operator_path(session)
  end

  test "launching a set while another is live redirects with an alert, not a 500" do
    live = @church.service_sets.create!(name: "Live")
    live.set_items.create!(position: 0, item_type: "song", song: @song)
    LiveSession.launch(live)

    other = @church.service_sets.create!(name: "Other")
    other.set_items.create!(position: 0, item_type: "song", song: @song)

    post launch_service_set_path(other)
    assert_redirected_to service_set_path(other)
    assert_match(/already live/i, flash[:alert])
  end

  test "launching a set that is already live resumes its own session" do
    mine = @church.service_sets.create!(name: "Mine")
    mine.set_items.create!(position: 0, item_type: "song", song: @song)
    session = LiveSession.launch(mine)

    post launch_service_set_path(mine)
    assert_redirected_to operator_path(session)
  end
end

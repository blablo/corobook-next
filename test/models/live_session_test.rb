require "test_helper"

class LiveSessionTest < ActiveSupport::TestCase
  setup do
    @church = Church.create!(name: "Central")
    @song = @church.songs.create!(title: "Himno", chordpro_source: "[G]Hola")
    @set = @church.service_sets.create!(name: "Domingo")
    @item0 = @set.set_items.create!(position: 0, item_type: "song", song: @song)
    @item1 = @set.set_items.create!(position: 1, item_type: "song",
                                    song: @church.songs.create!(title: "Dos", chordpro_source: "[C]y"))
  end

  test "launch seeds position at the first set item" do
    session = LiveSession.launch(@set)
    assert session.active?
    assert_equal @item0, session.current_set_item
    assert_equal 0, session.current_section_index
    assert_equal 0, session.position_version
    assert_equal @church, session.church
  end

  test "launch generates both follow tokens" do
    session = LiveSession.launch(@set)
    assert session.projector_token.present?
    assert session.musician_token.present?
    assert_not_equal session.projector_token, session.musician_token
  end

  test "tokens are unique across sessions" do
    s1 = LiveSession.launch(@set)
    s1.end!
    s2 = LiveSession.launch(@set)
    assert_not_equal s1.projector_token, s2.projector_token
  end

  test "ending the session revokes both tokens and marks it ended" do
    session = LiveSession.launch(@set)
    session.end!
    assert session.ended?
    assert_nil session.projector_token
    assert_nil session.musician_token
    assert session.ended_at.present?
  end

  test "two ended sessions with null tokens do not collide" do
    LiveSession.launch(@set).end!
    assert_nothing_raised { LiveSession.launch(@set).end! }
  end

  test "lock_version increments on update (optimistic locking)" do
    session = LiveSession.launch(@set)
    assert_equal 0, session.lock_version
    session.update!(current_section_index: 1)
    assert_equal 1, session.lock_version
  end

  test "a church cannot have two active sessions — a second launch is refused" do
    LiveSession.launch(@set)
    assert_raises(LiveSession::AlreadyLiveError) { LiveSession.launch(@set) }
    assert_equal 1, @church.live_sessions.where(status: "active").count
  end

  test "after ending the active session a new one can launch" do
    first = LiveSession.launch(@set)
    first.end!
    assert_nothing_raised { LiveSession.launch(@set) }
    assert_equal 1, @church.live_sessions.where(status: "active").count
  end

  test "the uniqueness validation rejects a second active session" do
    LiveSession.launch(@set)
    dup = @church.live_sessions.build(service_set: @set, status: "active")
    assert_not dup.valid?
  end

  test "the partial unique index blocks a validation bypass" do
    LiveSession.launch(@set)
    dup = @church.live_sessions.build(service_set: @set, status: "active")
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }
  end
end

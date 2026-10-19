require "test_helper"

class OperatorAdvanceTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    User.create!(church: @church, email: "op@example.com", password: "secret123", role: "editor")
    @song = @church.songs.create!(title: "Dos secciones",
      chordpro_source: "{sov: V1}\n[G]Uno\n{eov}\n{soc}\n[C]Coro\n{eoc}")
    @slide = @church.text_slides.create!(title: "Sermón", reusable: true)
    @set = @church.service_sets.create!(name: "Domingo")
    @i0 = @set.set_items.create!(position: 0, item_type: "song", song: @song)
    @i1 = @set.set_items.create!(position: 1, item_type: "text_slide", text_slide: @slide)
    @session = LiveSession.launch(@set)
    post login_path, params: { church_id: @church.id, email: "op@example.com", password: "secret123" }
  end

  test "advance walks sections within a song then crosses into the next item" do
    assert_equal @i0.id, @session.current_set_item_id
    assert_equal 0, @session.current_section_index

    patch operator_advance_path(@session)
    @session.reload
    assert_equal @i0.id, @session.current_set_item_id
    assert_equal 1, @session.current_section_index
    assert_equal 1, @session.position_version

    patch operator_advance_path(@session)
    @session.reload
    assert_equal @i1.id, @session.current_set_item_id
    assert_equal 0, @session.current_section_index
    assert_equal 2, @session.position_version
  end

  test "position_version increases monotonically and back decrements position but still bumps version" do
    patch operator_advance_path(@session)
    patch operator_advance_path(@session)
    @session.reload
    v = @session.position_version
    patch operator_back_path(@session)
    @session.reload
    assert_equal @i0.id, @session.current_set_item_id
    assert @session.position_version > v, "version must keep increasing even when moving back"
  end

  test "goto jumps to any item in the set" do
    patch operator_goto_path(@session, set_item_id: @i1.id)
    @session.reload
    assert_equal @i1.id, @session.current_set_item_id
    assert_equal 0, @session.current_section_index
  end

  test "optimistic locking surfaces a concurrent-operator conflict" do
    a = LiveSession.find(@session.id)
    b = LiveSession.find(@session.id)

    a.update!(current_section_index: 1) # DB lock_version 0 -> 1

    assert_raises(ActiveRecord::StaleObjectError) do
      b.update!(current_section_index: 2) # real change on a stale lock_version 0
    end
  end
end

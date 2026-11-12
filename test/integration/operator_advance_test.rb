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

  test "the operator page links back to the set" do
    get operator_path(@session)
    assert_response :success
    assert_select "[data-role=back-to-set][href='#{service_set_path(@set)}']"
  end

  test "the service order marks the current item and offers Go for the others" do
    get operator_path(@session)
    assert_select "[data-role=service-order] li[aria-current=true]", count: 1, text: /Dos secciones/
    assert_select "[data-role=service-order] [data-role=current-item]", count: 1
    assert_select "[data-role=service-order] form[action='#{operator_goto_path(@session, set_item_id: @i1.id)}']"
    assert_select "[data-role=service-order] form[action='#{operator_goto_path(@session, set_item_id: @i0.id)}']", count: 0
  end

  test "End service asks for confirmation before ending" do
    get operator_path(@session)
    assert_select "button[data-role=end-service][onclick*='end-service-modal']"
    assert_select "form[action='#{operator_end_path(@session)}']", count: 1
    assert_select "dialog#end-service-modal form[action='#{operator_end_path(@session)}'] [data-role=end-service-confirm]"
  end

  test "advance walks sections within a song then crosses into the next item" do
    # Section 0 is the song's title slide, 1 = V1, 2 = Coro, then the next item.
    assert_equal @i0.id, @session.current_set_item_id
    assert_equal 0, @session.current_section_index

    patch operator_advance_path(@session)
    @session.reload
    assert_equal @i0.id, @session.current_set_item_id
    assert_equal 1, @session.current_section_index
    assert_equal 1, @session.position_version

    patch operator_advance_path(@session)
    @session.reload
    assert_equal @i0.id, @session.current_set_item_id
    assert_equal 2, @session.current_section_index

    patch operator_advance_path(@session)
    @session.reload
    assert_equal @i1.id, @session.current_set_item_id
    assert_equal 0, @session.current_section_index
    assert_equal 3, @session.position_version
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

  test "the operator view shows projector/musician join links to copy and QR codes" do
    get operator_path(@session)
    assert_response :success
    # The QR codes open the follow pages; the chain buttons copy them.
    assert_select "a[data-role=projector-open][target=_blank][href$='/p/#{@session.projector_token}'] svg"
    assert_select "a[data-role=musician-open][target=_blank][href$='/m/#{@session.musician_token}'] svg"
    assert_select "[data-role=projector-copy][data-url*='/p/#{@session.projector_token}']"
    assert_select "[data-role=musician-copy][data-url*='/m/#{@session.musician_token}']"
    assert_select "[data-role=projector-copy][aria-label=?]", "Copy link: Projector"
  end

  test "each join code can be enlarged on its own, in a dialog over a blurred page" do
    get operator_path(@session)
    %w[projector musician speaker].each do |role|
      assert_select "[data-role=#{role}-enlarge][onclick*='#{role}-code-modal']"
      assert_select "dialog##{role}-code-modal.backdrop-blur-sm .modal-box a[data-role=#{role}-open-large] svg"
      assert_select "dialog##{role}-code-modal [data-role=#{role}-copy-large]"
    end
    assert_select "#projector-code-modal [data-role=projector-copy-large][data-url*='/p/#{@session.projector_token}']"
  end

  test "the join codes stay under the header after the service moves" do
    patch operator_advance_path(@session)
    get operator_path(@session)
    assert_select "details[data-role=join-links][open] [data-role=projector-copy]"
  end

  test "Connect devices stays closed for this service once closed, and the next service starts open" do
    cookies[:join_links_closed] = @session.id.to_s
    get operator_path(@session)
    assert_select "details[data-role=join-links]:not([open]) summary[data-role=join-links-toggle]", text: /Connect devices/
    assert_select "details[data-role=join-links][data-remember-open-key-value=?]", @session.id.to_s

    cookies[:join_links_closed] = (@session.id + 1).to_s
    get operator_path(@session)
    assert_select "details[data-role=join-links][open]"
  end
end

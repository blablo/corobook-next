require "test_helper"

# Keynote-style presenter view on the operator page: Now beside the real rendered Next slide.
class OperatorPresenterTest < ActionDispatch::IntegrationTest
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

  test "shows Now and the real next slide, with labels and position" do
    get operator_path(@session)
    assert_response :success

    # Stops: title, V1, Coro, Sermón.
    assert_select "[data-role=now-label]", text: "Dos secciones · Title"
    assert_select "[data-role=now-position]", text: "· Slide 1 of 4"
    assert_select "[data-role=next-label]", text: "Dos secciones · V1"
    assert_select "[data-role=next-frame] [data-role=projector-frame-preview] .projector-line", text: "Uno"
    assert_select "[data-role=clock][data-controller=clock]"
  end

  test "the next preview is static: one #live-frame and one follower controller only" do
    get operator_path(@session)

    assert_select "#live-frame", count: 1
    assert_select "[data-controller=follower]", count: 1
    assert_select "[data-role=next-frame] [data-controller=follower]", count: 0
  end

  test "rendering the preview never changes the live session" do
    before = @session.reload.attributes
    get operator_path(@session)
    assert_equal before, @session.reload.attributes
  end

  test "next names the next item when the song ends" do
    @session.update!(current_set_item: @i0, current_section_index: 2, current_chunk_index: 0)
    get operator_path(@session)

    assert_select "[data-role=now-position]", text: "· Slide 3 of 4"
    assert_select "[data-role=next-label]", text: "Sermón"
  end

  test "the last stop shows End of service instead of a next slide" do
    @session.update!(current_set_item: @i1, current_section_index: 0, current_chunk_index: 0)
    get operator_path(@session)

    assert_select "[data-role=end-of-service]", text: "End of service"
    assert_select "[data-role=next-label]", count: 0
    assert_select "[data-role=projector-frame-preview]", count: 0
  end

  test "when blanked, Now is marked blank but Next still shows the upcoming slide" do
    @session.update!(blanked: true)
    get operator_path(@session)

    assert_select "[data-role=blanked-badge]"
    assert_select "[data-role=operator-frame] [data-role=blank]"
    assert_select "[data-role=next-frame] [data-role=blank]", count: 0
    assert_select "[data-role=next-frame] .projector-line", text: "Uno"
  end
end

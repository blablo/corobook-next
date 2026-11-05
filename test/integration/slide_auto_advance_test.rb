require "test_helper"

# Auto-advance pages: a text slide whose pages turn by themselves on the projector.
class SlideAutoAdvanceTest < ActionDispatch::IntegrationTest
  PAGES = [ { "body_markdown" => "Bienvenidos" }, { "body_markdown" => "Kids" }, { "body_markdown" => "Oración" } ].freeze

  setup do
    @church = Church.create!(name: "Central")
    User.create!(church: @church, email: "op@example.com", password: "secret123", role: "editor")
    @slide = @church.text_slides.create!(title: "Anuncios", reusable: true, pages: PAGES, auto_advance_seconds: 6)
    @after = @church.text_slides.create!(title: "Sermón", reusable: true)
    @set = @church.service_sets.create!(name: "Domingo")
    @i0 = @set.set_items.create!(position: 0, item_type: "text_slide", text_slide: @slide)
    @i1 = @set.set_items.create!(position: 1, item_type: "text_slide", text_slide: @after)
    post login_path, params: { church_id: @church.id, email: "op@example.com", password: "secret123" }
  end

  test "model: off clears the interval, and a single page never auto-advances" do
    assert @slide.auto_advance?
    @slide.update!(auto_advance: "0", auto_advance_seconds: 6)
    assert_nil @slide.reload.auto_advance_seconds
    refute @slide.auto_advance?

    one = @church.text_slides.create!(title: "Uno", reusable: true, auto_advance_seconds: 5)
    refute one.auto_advance?
    refute @church.text_slides.build(title: "X", reusable: true, auto_advance_seconds: 1).valid?
    refute @church.text_slides.build(title: "X", reusable: true, auto_advance_transition: "spin").valid?
  end

  test "an auto-advancing slide is ONE operator stop; without it every page is a stop" do
    assert_equal 2, Corobook::LivePosition.new(@set).stops.length

    @slide.update!(auto_advance_seconds: nil)
    assert_equal 4, Corobook::LivePosition.new(@set.reload).stops.length
  end

  test "the projector renders every page under one shared clock" do
    session = LiveSession.launch(@set)
    get projector_path(session.projector_token)
    assert_response :success

    assert_select "[data-role=auto-pages][data-controller=auto-pages]" do |el|
      assert_equal "6", el.first["data-auto-pages-seconds-value"]
      assert_equal "true", el.first["data-auto-pages-loop-value"]
      assert_equal (session.position_since.to_f * 1000).to_i.to_s, el.first["data-auto-pages-since-value"]
    end
    assert_select "[data-role=auto-page]", count: 3
    assert_select "[data-role=auto-page].is-on", count: 1
    assert_select "[data-role=auto-page] .projector-slide-body", text: "Kids"
  end

  test "advancing records when the position moved, and Next leaves the whole slide" do
    session = LiveSession.launch(@set)
    travel 1.minute do
      patch operator_advance_path(session)
      session.reload
      assert_equal @i1.id, session.current_set_item_id
      assert_in_delta Time.current, session.position_changed_at, 1
    end
  end

  test "advancing from the projector clicker also restarts the page clock" do
    session = LiveSession.launch(@set)
    travel 1.minute do
      patch projector_advance_path(session.projector_token)
      session.reload
      assert_equal @i1.id, session.current_set_item_id
      assert_in_delta Time.current, session.position_changed_at, 1

      patch projector_back_path(session.projector_token)
      session.reload
      assert_equal @i0.id, session.current_set_item_id
      assert_in_delta Time.current, session.position_changed_at, 1
    end
  end

  test "operator: Now is labelled auto, with a page label the browser keeps current" do
    session = LiveSession.launch(@set)
    get operator_path(session)
    assert_select "[data-role=now-label]", text: "Anuncios · Page 1 of 3"
    assert_select "[data-role=now-panel] [data-role=auto-badge].badge", text: "↻ Auto · 6s"
    assert_select "[data-role=now-panel] progress[data-role=auto-progress][data-auto-page-label-target=progress]"
    assert_select "[data-role=now-label] [data-auto-page-label-target=text]", text: "Page 1 of 3"
    assert_select "[data-role=now-position]", text: "Slide 1 of 2"
    assert_select "[data-role=now-panel][data-controller=auto-page-label]"
  end

  test "the Next preview of an auto slide starts its own clock (since = 0)" do
    @set.set_items.where(id: @i0.id).update_all(position: 2)
    @i1.update!(position: 0)
    session = LiveSession.launch(@set.reload)
    get operator_path(session)

    assert_select "[data-role=next-frame] [data-role=auto-pages][data-auto-pages-since-value='0']"
    # The coming slide is flagged too; Now (a normal slide) has no badge or bar.
    assert_select "[data-role=next-panel] [data-role=auto-badge]"
    assert_select "[data-role=now-panel] [data-role=auto-badge]", count: 0
    assert_select "[data-role=auto-progress]", count: 0
  end

  test "the editor saves the auto-advance options" do
    patch text_slide_path(@slide), params: { text_slide: {
      title: "Anuncios", pages: PAGES, auto_advance: "1", auto_advance_seconds: "10",
      auto_advance_loop: "0", auto_advance_transition: "cut"
    } }
    @slide.reload
    assert_equal 10, @slide.auto_advance_seconds
    refute @slide.auto_advance_loop
    assert_equal "cut", @slide.auto_advance_transition

    patch text_slide_path(@slide), params: { text_slide: { title: "Anuncios", pages: PAGES, auto_advance: "0", auto_advance_seconds: "10" } }
    assert_nil @slide.reload.auto_advance_seconds
  end

  test "the editor shows the toggle, options and preview play controls" do
    get edit_text_slide_path(@slide)
    assert_response :success
    # Collapsed to start; the title still says whether it is on.
    assert_select "details[data-role=auto-advance]:not([open])"
    assert_select "[data-role=auto-advance-summary]", text: "· On, every 6s"
    assert_select "[data-role=auto-advance] input[type=checkbox].toggle[checked]"
    assert_select "[data-role=auto-advance] input[name='text_slide[auto_advance_seconds]'][value='6']"
    assert_select "[data-role=auto-advance] select[name='text_slide[auto_advance_transition]']"
    assert_select "[data-role=auto-pause]"
    assert_select "progress[data-role=auto-progress]"
  end
end

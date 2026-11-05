require "test_helper"

# Countdown fields in text slides: projector rendering, the operator badge and the editor.
class SlideCountdownIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    User.create!(church: @church, email: "op@example.com", password: "secret123", role: "editor")
    @slide = @church.text_slides.create!(title: "Bienvenida", reusable: true,
      pages: [ { "body_markdown" => "El servicio empieza en {{countdown 10:30 | ¡Comenzamos!}}" } ])
    @plain = @church.text_slides.create!(title: "Sermón", reusable: true)
    @set = @church.service_sets.create!(name: "Domingo")
    @set.set_items.create!(position: 0, item_type: "text_slide", text_slide: @slide)
    @set.set_items.create!(position: 1, item_type: "text_slide", text_slide: @plain)
    @session = LiveSession.launch(@set)
    post login_path, params: { church_id: @church.id, email: "op@example.com", password: "secret123" }
  end

  test "the projector renders a live countdown and the shared start time" do
    get projector_path(@session.projector_token)
    assert_response :success
    assert_select "#live-frame[data-live-since='#{(@session.position_since.to_f * 1000).to_i}'][data-server-now]"
    assert_select "#live-frame span.slide-countdown[data-countdown-to-value='10:30'][data-countdown-end-value='¡Comenzamos!']"
  end

  test "the operator's Now card shows a countdown badge only for a countdown slide" do
    get operator_path(@session)
    assert_select "[data-role=now-panel] [data-role=countdown-badge][data-auto-page-label-target=countdown]"
    assert_select "[data-role=now-panel][data-action*='countdown:tick->auto-page-label#countdown']"

    patch operator_advance_path(@session)
    get operator_path(@session)
    assert_select "[data-role=countdown-badge]", count: 0
  end

  test "the editor offers the countdown button and a dialog that submits nothing" do
    get edit_text_slide_path(@slide)
    assert_response :success
    assert_select "[data-role=countdown-button]"
    assert_select "dialog[data-role=countdown-dialog]" do
      assert_select "form", count: 0
      # Only the mode radios are named, and they belong to no form.
      assert_select "input[name]", count: 2
      assert_select "input[name=countdown_mode][form=slide-countdown-unsubmitted]", count: 2
    end
  end

  test "saving keeps the marker, and the preview endpoint renders it live" do
    md = "Volvemos en {{countdown 5m}}"
    patch text_slide_path(@slide), params: { text_slide: { title: "Bienvenida", pages: [ { body_markdown: md } ] } }
    assert_equal md, @slide.reload.page_markdown(0)

    post preview_text_slides_path, params: { body_markdown: md }, as: :json
    assert_includes response.parsed_body["html"], %(data-countdown-minutes-value="5")
  end
end

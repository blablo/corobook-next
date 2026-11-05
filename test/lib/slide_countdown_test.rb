require "test_helper"

class SlideCountdownTest < ActiveSupport::TestCase
  def render(md) = Corobook::SlideCountdown.render(Commonmarker.to_html(md))

  def span(md) = Nokogiri::HTML.fragment(render(md)).at_css("span.slide-countdown[data-controller=countdown]")

  test "a time-of-day marker becomes a live span with its end text" do
    s = span("Empieza en {{countdown 10:30 | ¡Comenzamos!}}")
    assert_equal "10:30", s["data-countdown-to-value"]
    assert_equal "¡Comenzamos!", s["data-countdown-end-value"]
    assert_nil s["data-countdown-minutes-value"]
  end

  test "a duration marker counts minutes and an empty end text holds at zero" do
    s = span("Volvemos en **{{countdown 5m}}**")
    assert_equal "5", s["data-countdown-minutes-value"]
    assert_equal "", s["data-countdown-end-value"]
  end

  test "quotes in the end text cannot break out of the attribute" do
    html = render(%({{countdown 9:05 | say "hi" & go}}))
    s = Nokogiri::HTML.fragment(html).at_css("span.slide-countdown")
    assert_equal %(say "hi" & go), s["data-countdown-end-value"]
    assert_equal 1, Nokogiri::HTML.fragment(html).css("span").size
  end

  test "malformed markers and raw HTML stay inert text" do
    assert_nil span("{{countdown 99:xx}}")
    html = render("{{countdown 10:30 | <script>x</script>}}")
    assert_nil Nokogiri::HTML.fragment(html).at_css("script, span.slide-countdown")
  end

  test "present? and TextSlide#countdown? detect a marker on any page" do
    church = Church.create!(name: "Central")
    slide = church.text_slides.create!(title: "Bienvenida", reusable: true,
      pages: [ { "body_markdown" => "Hola" }, { "body_markdown" => "En {{countdown 5m}}" } ])
    assert slide.countdown?
    refute church.text_slides.create!(title: "Sin", reusable: true).countdown?
    assert_includes slide.rendered_html(1), "slide-countdown"
  end
end

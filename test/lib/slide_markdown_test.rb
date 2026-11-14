require "test_helper"

class SlideMarkdownTest < ActiveSupport::TestCase
  def render(md) = Corobook::SlideMarkdown.render(md)

  test "~text~ is small text, inline or as a whole line" do
    assert_includes render("Body\n\n~(Psalm 25:6-8)~"), %(<sub class="slide-small">(Psalm 25:6-8)</sub>)
    assert_includes render("said ~(v. 3)~ then"), %(said <sub class="slide-small">(v. 3)</sub> then)
  end

  test "small text keeps formatting inside it" do
    assert_includes render("~[ªGreek, *hades*]~"), %(<sub class="slide-small">[ªGreek, <em>hades</em>]</sub>)
  end

  test "~~text~~ stays strikethrough and an escaped or spaced tilde is literal" do
    assert_includes render("keep ~~this~~"), "<del>this</del>"
    refute_includes render("5 \\~ 6 and a ~ b ~ c"), "<sub"
  end

  test "line breaks, raw HTML escaping and countdowns behave as before" do
    html = render("one\ntwo <script>x</script> {{countdown 5m}}")
    assert_includes html, "one<br />"
    refute_includes html, "<script>"
    assert_includes html, %(data-role="countdown")
  end

  test "a slide page renders through it" do
    church = Church.create!(name: "Central")
    slide = church.text_slides.create!(title: "S", reusable: true, pages: [ { "body_markdown" => "~(Ref 1:1)~" } ])
    assert_includes slide.rendered_html(0), %(class="slide-small")
  end
end

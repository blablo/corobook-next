require "test_helper"

class TextSlideTest < ActiveSupport::TestCase
  setup { @church = Church.create!(name: "Central") }

  def slide(**attrs)
    @church.text_slides.build({ title: "Credo", pages: [ { "body_markdown" => "**Creo**" } ] }.merge(attrs))
  end

  test "a reusable slide has no owning set" do
    s = slide(reusable: true)
    assert s.valid?, s.errors.full_messages.to_sentence
    assert s.save
    assert_nil s.set_id
  end

  test "a reusable slide with a set_id is invalid" do
    assert_not slide(reusable: true, set_id: 999).valid?
  end

  test "an inline slide requires an owning set" do
    assert_not slide(reusable: false, set_id: nil).valid?
    assert slide(reusable: false, set_id: 123).valid?
  end

  test "markdown is rendered to HTML per page" do
    s = slide(pages: [ { "body_markdown" => "**Creo**" }, { "body_markdown" => "_mas_" } ])
    assert_equal "<p><strong>Creo</strong></p>\n", s.rendered_html(0)
    assert_equal "<p><em>mas</em></p>\n", s.rendered_html(1)
    assert_equal 2, s.page_count
  end

  test "raw HTML in a page is escaped, not emitted" do
    s = slide(pages: [ { "body_markdown" => "Hola <script>alert(1)</script>" } ])
    assert_not_includes s.rendered_html, "<script>"
  end

  test "tags are trimmed, lower-cased, and de-duplicated" do
    s = slide(tags: [ " Advent ", "SCRIPTURE", "scripture", "" ])
    s.valid?
    assert_equal %w[advent scripture], s.tags
  end

  test "pages normalize to at least one page" do
    s = slide(pages: [])
    s.valid?
    assert_equal 1, s.page_count
    assert_equal "", s.page_markdown(0)
  end

  test "tagged scope finds slides carrying a tag, case-insensitively" do
    @church.text_slides.create!(title: "A", tags: [ "advent" ], pages: [ { "body_markdown" => "x" } ])
    @church.text_slides.create!(title: "B", tags: [ "lent" ], pages: [ { "body_markdown" => "y" } ])
    assert_equal [ "A" ], @church.text_slides.tagged("Advent").pluck(:title)
  end

  test "search matches a tag" do
    @church.text_slides.create!(title: "Credo", tags: [ "statement_of_faith" ], pages: [ { "body_markdown" => "Creo" } ])
    assert_equal 1, @church.text_slides.search("faith").count
  end
end

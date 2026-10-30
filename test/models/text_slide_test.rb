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

  test "text is centered both ways by default" do
    s = slide
    assert_equal [ "center", "center" ], [ s.text_align, s.vertical_align ]
    assert_equal "slide-align-center slide-valign-center", s.alignment_classes
  end

  test "alignment accepts only the offered positions" do
    assert slide(text_align: "left", vertical_align: "bottom").valid?
    assert_not slide(text_align: "justify").valid?
    assert_not slide(vertical_align: "middle").valid?
  end

  test "an inline slide requires an owning set" do
    assert_not slide(reusable: false, set_id: nil).valid?
    assert slide(reusable: false, set_id: 123).valid?
  end

  test "accepts a valid background image and reports it attached" do
    s = slide(bg_type: "image")
    s.background_image.attach(io: File.open(Rails.root.join("test/fixtures/files/bg.png")),
                              filename: "bg.png", content_type: "image/png")
    assert s.valid?, s.errors.full_messages.to_sentence
    assert s.save
    assert s.background_image?
  end

  test "an attached image only shows in Image mode" do
    s = slide(bg_type: "gradient")
    s.background_image.attach(io: File.open(Rails.root.join("test/fixtures/files/bg.png")),
                              filename: "bg.png", content_type: "image/png")
    s.save!
    assert_not s.background_image?
  end

  test "default look is black background, white sans-serif text" do
    assert_equal "--proj-bg: #000000; --proj-text: #ffffff; --proj-font: #{Corobook::ProjectorSettings::FONT_STACKS['sans']}",
                 slide.projector_style
  end

  test "gradient look uses both colours and the angle" do
    s = slide(bg_type: "gradient", bg_color: "#112233", bg_color2: "#445566", bg_gradient_angle: 90,
              text_color: "#ffee00", font: "serif")
    assert_includes s.projector_style, "--proj-bg: linear-gradient(90deg, #112233, #445566)"
    assert_includes s.projector_style, "--proj-text: #ffee00"
    assert_includes s.projector_style, "Georgia"
  end

  test "look values are validated like the song settings" do
    assert_not slide(bg_type: "video").valid?
    assert_not slide(bg_color: "red").valid?
    assert_not slide(text_color: "#12345").valid?
    assert_not slide(bg_gradient_angle: 400).valid?
    assert_not slide(font: "comic").valid?
  end

  test "rejects a background image of the wrong content type" do
    s = slide
    s.background_image.attach(io: StringIO.new("not an image"),
                              filename: "evil.txt", content_type: "text/plain")
    assert_not s.valid?
    assert s.errors[:background_image].any?
  end

  test "a slide without a background image reports not attached" do
    assert_not slide.background_image?
  end

  test "font size defaults to auto (nil) and accepts a size in range" do
    assert_nil slide.font_size
    assert slide(font_size: 10).valid?
  end

  test "font size outside 2..30 is invalid" do
    assert_not slide(font_size: 1).valid?
    assert_not slide(font_size: 31).valid?
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

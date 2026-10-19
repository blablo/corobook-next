require "test_helper"

class TextSlideTest < ActiveSupport::TestCase
  setup { @church = Church.create!(name: "Central") }

  def slide(**attrs)
    @church.text_slides.build({ title: "Credo", subtype: "statement_of_faith", body_markdown: "**Creo**" }.merge(attrs))
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

  test "markdown is rendered to HTML" do
    assert_equal "<p><strong>Creo</strong></p>\n", slide.rendered_html
  end

  test "raw HTML in markdown is escaped, not emitted" do
    s = slide(body_markdown: "Hola <script>alert(1)</script>")
    assert_not_includes s.rendered_html, "<script>"
  end

  test "subtype is constrained" do
    assert_not slide(subtype: "nonsense").valid?
    s = slide(subtype: "nonsense")
    assert_raises(ActiveRecord::StatementInvalid) do
      s.subtype = "statement"
      s.save!
      Song.connection.execute("UPDATE text_slides SET subtype = 'nonsense' WHERE id = #{s.id}")
    end
  end

  test "subtype_class dasherizes the subtype" do
    assert_equal "slide-statement-of-faith", slide(subtype: "statement_of_faith").subtype_class
  end
end

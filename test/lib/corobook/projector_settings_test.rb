require "test_helper"

class Corobook::ProjectorSettingsTest < ActiveSupport::TestCase
  test "style emits every projector CSS variable from the church columns" do
    church = Church.create!(name: "Looks",
      projector_bg_color: "#102030", projector_text_color: "#fafafa",
      projector_font: "serif", projector_line_height: "relaxed",
      projector_bold: false, projector_valign: "top",
      projector_lyric_case: "upper", projector_title_case: "title")
    style = church.projector_settings.style

    assert_includes style, "--proj-bg: #102030"
    assert_includes style, "--proj-text: #fafafa"
    assert_includes style, "Georgia"            # serif stack
    assert_includes style, "--proj-line-height: 1.4"
    assert_includes style, "--proj-weight: 400" # bold off
    assert_includes style, "--proj-valign: flex-start"
    assert_includes style, "--proj-lyric-case: uppercase"
    assert_includes style, "--proj-title-case: capitalize"
  end

  test "defaults reproduce the classic black/white centered look" do
    style = Church.create!(name: "Default").projector_settings.style
    assert_includes style, "--proj-bg: #000000"
    assert_includes style, "--proj-text: #ffffff"
    assert_includes style, "--proj-weight: 700"
    assert_includes style, "--proj-valign: center"
    assert_includes style, "--proj-lyric-case: none"
  end

  test "rejects a non-hex colour and an out-of-range line count" do
    church = Church.new(name: "Bad", projector_bg_color: "black", projector_lines_per_slide: 99)
    refute church.valid?
    assert church.errors[:projector_bg_color].any?
    assert church.errors[:projector_lines_per_slide].any?
  end

  test "rejects an unknown enum value" do
    church = Church.new(name: "Bad", projector_font: "comic-sans", projector_valign: "middle")
    refute church.valid?
    assert church.errors[:projector_font].any?
    assert church.errors[:projector_valign].any?
  end
end

require "test_helper"

class Corobook::ChordPro::ChorusReplayTest < ActiveSupport::TestCase
  def parse(src) = Corobook::ChordPro::Parser.parse(src)

  test "materializes the most recent chorus into concrete lines" do
    src = <<~CP
      {soc}
      Gloria [G]a Dios
      {eoc}
      {sov: Verso}
      Texto
      {eov}
      {chorus}
    CP
    sections = parse(src).sections
    replay = sections.last
    original = sections.first

    assert_equal "chorus", replay["kind"]
    assert_equal original["lines"], replay["lines"], "replay must carry a concrete copy of the chorus lines"
    assert replay.key?("replay_of")
  end

  test "the replay is a deep copy, independent of the original" do
    src = "{soc}\nGloria [G]a Dios\n{eoc}\n{chorus}\n"
    sections = parse(src).sections
    refute_same sections.first["lines"], sections.last["lines"]
    assert_equal sections.first["lines"].first, sections.last["lines"].first
  end

  test "a {chorus} with no prior chorus produces an empty warned section" do
    sections = parse("{sov: V}\nTexto\n{eov}\n{chorus}\n").sections
    replay = sections.last
    assert_equal [], replay["lines"]
    assert_match "x_corobook_parse_warning", replay["x_corobook_parse_warning"]
  end
end

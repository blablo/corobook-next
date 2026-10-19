require "test_helper"

class Corobook::ChordPro::ParserTest < ActiveSupport::TestCase
  def parse(src) = Corobook::ChordPro::Parser.parse(src)

  test "normalizes CRLF and CR to LF" do
    parsed = parse("Line one\r\nLine two\rLine three")
    lines = parsed.sections.first["lines"]
    assert_equal 3, lines.length
  end

  test "binds an inline chord to the text that follows it" do
    parsed = parse("Yo soy la [G]sal de la [D]tierra")
    segs = parsed.sections.first["lines"].first["segments"]
    assert_equal({ "text" => "Yo soy la ", "chord" => nil }, segs[0])
    assert_equal({ "text" => "sal de la ", "chord" => "G" }, segs[1])
    assert_equal({ "text" => "tierra", "chord" => "D" }, segs[2])
  end

  test "supports a mid-word chord with no word boundary" do
    parsed = parse("ca[G]sa")
    segs = parsed.sections.first["lines"].first["segments"]
    assert_equal({ "text" => "ca", "chord" => nil }, segs[0])
    assert_equal({ "text" => "sa", "chord" => "G" }, segs[1])
  end

  test "a line starting with a chord has no leading empty segment" do
    parsed = parse("[G]casa")
    segs = parsed.sections.first["lines"].first["segments"]
    assert_equal [ { "text" => "casa", "chord" => "G" } ], segs
  end

  test "reads title, subtitle, key, capo and transpose into meta" do
    parsed = parse("{title: Himno}\n{subtitle: Autor}\n{key: G}\n{capo: 2}\n{transpose: -1}\nHola")
    assert_equal "Himno", parsed.meta["title"]
    assert_equal "Autor", parsed.meta["subtitle"]
    assert_equal "G", parsed.meta["key"]
    assert_equal 2, parsed.meta["capo"]
    assert_equal(-1, parsed.meta["transpose"])
  end

  test "opens labeled sections with short and long directive forms" do
    parsed = parse("{start_of_verse: Verso 1}\nTexto\n{eov}\n{soc}\nCoro\n{eoc}")
    verse, chorus = parsed.sections
    assert_equal "Verso 1", verse["label"]
    assert_equal "verse", verse["kind"]
    assert_equal false, verse["is_chorus"]
    assert_equal "chorus", chorus["kind"]
    assert_equal true, chorus["is_chorus"]
  end

  test "falls back to blank-line grouping when no section directive is present" do
    parsed = parse("Verso uno\nlinea dos\n\nVerso dos")
    assert_equal 2, parsed.sections.length
    assert_equal :none.to_s, parsed.sections.first["kind"]
  end

  test "ignores an unknown directive without raising" do
    parsed = parse("{x_unknown_thing: whatever}\nHola")
    assert_equal 1, parsed.sections.length
    assert_equal "Hola", parsed.sections.first["lines"].first["segments"].first["text"]
  end

  test "captures a chord-only line as empty-text segments" do
    parsed = parse("[G][C][D]")
    segs = parsed.sections.first["lines"].first["segments"]
    assert_equal [
      { "text" => "", "chord" => "G" },
      { "text" => "", "chord" => "C" },
      { "text" => "", "chord" => "D" }
    ], segs
  end

  test "an empty source produces a well-formed empty document" do
    parsed = parse("")
    assert_equal 1, parsed.version
    assert_equal [], parsed.sections
  end

  test "never raises on malformed brackets" do
    assert_nothing_raised { parse("hola [G mundo sin cerrar") }
  end
end

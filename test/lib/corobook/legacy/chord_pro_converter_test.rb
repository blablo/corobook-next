require "test_helper"

class Corobook::Legacy::ChordProConverterTest < ActiveSupport::TestCase
  def convert(lyric, **opts) = Corobook::Legacy::ChordProConverter.convert(lyric, **opts)

  test "places a chord above the column of its lyric grapheme" do
    legacy = "G       C\nHOLA MUNDO"
    #          col0    col8 → grapheme index 8 is the second 'D' position
    out = convert(legacy)
    assert_equal "[G]HOLA MUN[C]DO", out
  end

  test "a leading chord at column 0 attaches to the first grapheme" do
    legacy = "C\nHOLA"
    assert_equal "[C]HOLA", convert(legacy)
  end

  test "section headers become section directives" do
    legacy = "[VERSE 1]\nD\nHOLA\n[CHOIR]\nG\nCORO"
    out = convert(legacy)
    assert_includes out, "{sov: Verse 1}"
    assert_includes out, "{soc}"
  end

  test "tabs are expanded before column math" do
    # A tab then a chord; tab expands to 8 spaces so the chord sits at column 8.
    legacy = "\tG\nXXXXXXXXY"
    out = convert(legacy)
    assert_includes out, "[G]Y"
  end

  test "repeat markers are stripped" do
    legacy = "G\n// HOLA //"
    out = convert(legacy)
    assert_not_includes out, "//"
    assert_includes out, "HOLA"
  end

  test "the combining-ring diminished chord survives as a chord token" do
    legacy = "C C°                   Dm\n   CUAN BELLO ES EL SEÑOR"
    out = convert(legacy)
    assert_includes out, "[C°]"
    assert_includes out, "[C]"
    assert_includes out, "[Dm]"
    # Every lyric grapheme is preserved (chords are interleaved, not replacing letters).
    assert_equal "CUAN BELLO ES EL SEÑOR", out.gsub(/\[[^\]]*\]/, "").strip
  end

  test "order becomes an arrangement array" do
    conv = Corobook::Legacy::ChordProConverter.new("G\nHOLA", order: "VERSE 1, CHOIR, VERSE 2")
    conv.convert
    assert_equal [ "VERSE 1", "CHOIR", "VERSE 2" ], conv.arrangement
  end

  test "mood becomes a custom directive" do
    out = convert("G\nHOLA", mood: 3)
    assert_includes out, "{x_corobook_mood: 3}"
  end

  test "accented capitals count as single grapheme columns" do
    # Ñ is one column; the chord after it lands correctly.
    legacy = "  G\nSEÑOR"
    #           ^2 -> grapheme index 2 = Ñ
    out = convert(legacy)
    assert_includes out, "SE[G]ÑOR"
  end

  test "spanish and variant section headers resolve to directives" do
    assert_includes convert("[VERSO 1]\nG\nHOLA"), "{sov: Verso 1}"
    assert_includes convert("[CORO]\nG\nHOLA"), "{soc}"
    assert_includes convert("[PUENTE]\nG\nHOLA"), "{sob}"
    assert_includes convert("[FIN]\nG\nHOLA"), "{sov}"
    # glued identifier (VERSOA), punctuation (VERSE.2), trailing language tag (COROES)
    assert_includes convert("[VERSOA]\nG\nHOLA"), "{sov: Verso A}"
    assert_includes convert("[VERSE.2]\nG\nHOLA"), "{sov: Verse 2}"
    assert_includes convert("[COROES]\nG\nHOLA"), "{soc}"
    # base term as the trailing word
    assert_includes convert("[PRIMERA PARTE]\nG\nHOLA"), "{sov:"
  end

  test "never raises on a ragged or malformed blob" do
    assert_nothing_raised { convert("G C D\n") }
    assert_nothing_raised { convert("\n\n[WEIRD]\nstuff") }
  end
end

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
    legacy = "[VERSE 1]\nD\nHOLA\n[CHOIR]\nG\nLALA"
    out = convert(legacy)
    assert_includes out, "{sov: Verse 1}"
    assert_includes out, "{soc: Chorus}"
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

  test "slash runs of any length are stripped but slash chords survive" do
    assert_not_includes convert("G\n///HOLA///"), "/"
    # a slash INSIDE a chord token (D/F#) must survive
    assert_includes convert("D/F#\nHOLA"), "[D/F#]"
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

  test "order becomes a canonical English arrangement array" do
    conv = Corobook::Legacy::ChordProConverter.new("G\nHOLA", order: "VERSO 1, CORO, VERSE 2, FIN")
    conv.convert
    assert_equal [ "Verse 1", "Chorus", "Verse 2", "Outro" ], conv.arrangement
  end

  test "section labels and arrangement are standardized to English" do
    assert_includes convert("[VERSO 1]\nG\nHOLA"), "{sov: Verse 1}"
    assert_includes convert("[CORO 2]\nG\nHOLA"), "{soc: Chorus 2}"
    assert_includes convert("[PUENTE]\nG\nHOLA"), "{sob: Bridge}"
    assert_includes convert("[PRECORO]\nG\nHOLA"), "{sob: Pre-chorus}"
    assert_includes convert("[FINAL]\nG\nHOLA"), "{sov: Outro}"
    assert_includes convert("[INTRO]\nG\nHOLA"), "{sov: Intro}"
    # letter / odd suffixes collapse to the number (or drop)
    assert_includes convert("[VERSO 2A]\nG\nHOLA"), "{sov: Verse 2}"
    assert_includes convert("[CORO MACABRO]\nG\nHOLA"), "{soc: Chorus}"
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

  test "variant, glued, punctuated and language-tagged headers resolve and standardize" do
    assert_includes convert("[VERSO 1]\nG\nHOLA"), "{sov: Verse 1}"
    assert_includes convert("[CORO]\nG\nHOLA"), "{soc: Chorus}"
    assert_includes convert("[PUENTE]\nG\nHOLA"), "{sob: Bridge}"
    assert_includes convert("[FIN]\nG\nHOLA"), "{sov: Outro}"
    # glued identifier (VERSOA → number dropped, no digit), punctuation (VERSE.2), language tag (COROES)
    assert_includes convert("[VERSO1]\nG\nHOLA"), "{sov: Verse 1}"
    assert_includes convert("[VERSE.2]\nG\nHOLA"), "{sov: Verse 2}"
    assert_includes convert("[COROES]\nG\nHOLA"), "{soc: Chorus}"
    # base term as the trailing word
    assert_includes convert("[PRIMERA PARTE]\nG\nHOLA"), "{sov: Verse"
  end

  test "never raises on a ragged or malformed blob" do
    assert_nothing_raised { convert("G C D\n") }
    assert_nothing_raised { convert("\n\n[WEIRD]\nstuff") }
  end
end

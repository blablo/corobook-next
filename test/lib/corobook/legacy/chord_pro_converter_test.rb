require "test_helper"

class Corobook::Legacy::ChordProConverterTest < ActiveSupport::TestCase
  def convert(lyric, **opts) = Corobook::Legacy::ChordProConverter.convert(lyric, **opts)

  test "a standalone chord line (intro, no lyric beneath) becomes a spaced progression" do
    # A chord line followed by a blank line / section — not merged onto an empty line, and
    # each chord gets its own run of spaces so pills don't collide.
    assert_equal "{sov: Intro}\n[G]    [C]    [D]    [G]\n", convert("[INTRO]\nG  C  D  G\n")
    # and it must NOT collapse all chords to column 0
    assert_not_includes convert("[INTRO]\nG  C  D  G\n"), "[G][C]"
  end

  test "a // repeat block is preserved as a ×2 annotation, slashes stripped" do
    out = convert("//Canta otra vez\ny otra vez//")
    assert_not_includes out, "/"
    assert_includes out, "Canta otra vez"
    assert_includes out, "{comment: ×2}"
  end

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

  test "single leading/trailing repeat slashes and slash-wrapped chords are cleaned" do
    # a single slash opening or closing a lyric line is a repeat marker, not text
    assert_equal "[G]Sonrie", convert("G\n/Sonrie")
    assert_equal "Alabare mi [G]Jesus", convert("           G\nAlabare mi Jesus/")
    # a chord wrapped in slashes on a chord-only line becomes a clean progression, no slashes
    out = convert("A    B    /A-E/")
    assert_includes out, "[A]"
    assert_includes out, "[B]"
    assert_includes out, "[A-E]"
    assert_not_includes out, "/"
    # a time signature like 3/4 inside a lyric is NOT a repeat marker and is preserved
    assert_includes convert("G\n3/4 Alabanza"), "3/4"
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

  test "mood is accepted but never emitted (no consumer in corobook-next)" do
    out = convert("G\nHOLA", mood: 3)
    assert_not_includes out, "x_corobook_mood"
    assert_not_includes out, "{"
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

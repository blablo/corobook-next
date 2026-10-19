require "test_helper"

class Corobook::ChordPro::TransformTest < ActiveSupport::TestCase
  def parse(src) = Corobook::ChordPro::Parser.parse(src)
  def chords_of(parsed)
    parsed.sections.flat_map { |s| s["lines"].flat_map { |l| (l["segments"] || []).filter_map { |seg| seg["chord"] } } }
  end

  test "transposes every chord in the song" do
    parsed = parse("{key: G}\n[G]Hola [C]mundo [D]hoy")
    out = Corobook::ChordPro::Transform.transpose(parsed, semitones: 2)
    assert_equal %w[A D E], chords_of(out)
  end

  test "applies the meta transpose baseline before the requested shift" do
    # baseline −2 then +0 → chords drop two semitones. Key G → sharp spelling.
    parsed = parse("{key: G}\n{transpose: -2}\n[G]Hola [C]mundo")
    out = Corobook::ChordPro::Transform.transpose(parsed, semitones: 0)
    assert_equal %w[F A#], chords_of(out)
  end

  test "baseline and follower shift combine" do
    parsed = parse("{key: G}\n{transpose: -2}\n[G]Hola")
    out = Corobook::ChordPro::Transform.transpose(parsed, semitones: 2) # -2 + 2 = 0
    assert_equal %w[G], chords_of(out)
  end

  test "capo shifts the displayed chords down with key-appropriate spelling" do
    # Key F → flat spelling: C down 2 is Bb.
    parsed = parse("{key: F}\n[F]Hola [C]mundo")
    out = Corobook::ChordPro::Transform.transpose(parsed, capo: 2)
    assert_equal %w[Eb Bb], chords_of(out)
  end

  test "an unparsed chord passes through unchanged" do
    parsed = parse("[Fm#]Hola")
    out = Corobook::ChordPro::Transform.transpose(parsed, semitones: 3)
    assert_equal %w[Fm#], chords_of(out)
  end

  test "the transform does not mutate the input" do
    parsed = parse("{key: G}\n[G]Hola")
    Corobook::ChordPro::Transform.transpose(parsed, semitones: 5)
    assert_equal %w[G], chords_of(parsed)
  end

  test "plain_text strips chords and rejoins mid-word segments" do
    parsed = parse("Yo soy la [G]sal de la [D]tierra\nca[G]sa")
    assert_equal "Yo soy la sal de la tierra\ncasa", Corobook::ChordPro::Transform.plain_text(parsed)
  end

  test "plain_text omits directives and chord-only lines produce blank text" do
    parsed = parse("{title: X}\n{soc}\nGloria a Dios\n[G][C]\n{eoc}")
    assert_equal "Gloria a Dios\n", Corobook::ChordPro::Transform.plain_text(parsed)
  end
end

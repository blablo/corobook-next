require "test_helper"

class Corobook::ChordTransposeTest < ActiveSupport::TestCase
  def t(src, semis, **opts) = Corobook::Chord.parse(src).transpose(semis, **opts).to_s

  test "transposing up preserves quality and extension" do
    assert_equal "A", t("G", 2)
    assert_equal "F#m7", t("Em7", 2)
    assert_equal "Gmaj7", t("Fmaj7", 2)
  end

  test "transposing down wraps around the octave" do
    assert_equal "B", t("C", -1)
    assert_equal "A#", t("C", -2, prefer: :sharps)
  end

  test "enharmonic spelling follows the preference" do
    assert_equal "A#", t("A", 1, prefer: :sharps)
    assert_equal "Bb", t("A", 1, prefer: :flats)
  end

  test "spelling_for picks flats for flat keys and sharps otherwise" do
    assert_equal :flats, Corobook::Chord.spelling_for("F")
    assert_equal :flats, Corobook::Chord.spelling_for("Bb")
    assert_equal :sharps, Corobook::Chord.spelling_for("G")
    assert_equal :sharps, Corobook::Chord.spelling_for(nil)
  end

  test "the bass note transposes with the chord" do
    assert_equal "E/G#", t("D/F#", 2, prefer: :sharps)
    assert_equal "Em/G", t("Dm/F", 2, prefer: :sharps)
  end

  test "an unparsed chord is returned unchanged" do
    c = Corobook::Chord.parse("Fm#")
    assert c.unparsed?
    assert_equal "Fm#", c.transpose(5).to_s
  end

  test "a zero shift returns the chord unchanged" do
    assert_equal "Cmaj7/G", t("Cmaj7/G", 0)
  end

  test "capo displays the chord transposed down by the fret count" do
    # Sounding G, capo 2 → the guitarist plays an F shape.
    assert_equal "F", Corobook::Chord.parse("G").capo(2).to_s
    assert_equal "C", Corobook::Chord.parse("D").capo(2).to_s
    assert_equal "G", Corobook::Chord.parse("G").capo(0).to_s
  end

  test "capo leaves an unparsed chord unchanged" do
    assert_equal "Fm#", Corobook::Chord.parse("Fm#").capo(3).to_s
  end
end

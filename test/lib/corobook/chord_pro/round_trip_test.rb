require "test_helper"

class Corobook::ChordPro::RoundTripTest < ActiveSupport::TestCase
  CORPUS = [
    "Yo soy la [G]sal de la [D]tierra",
    "ca[G]sa",                       # mid-word chord
    "[G][D]word",                    # consecutive chords, no space
    "[G] [D]word",                   # space between chords (lives in text)
    "[G][C][D]",                     # chord-only line
    "{title: Himno}\n{key: G}\n{soc}\nGloria [G]a Dios\n{eoc}",
    "{sov: Verso 1}\nPrimera [C]linea\nSegunda linea\n{eov}",
    "  leading and trailing spaces  ",
    "C\u00B0 combining ring handled as text [C\u00B0]nota"
  ].freeze

  CORPUS.each_with_index do |src, i|
    test "round-trips corpus fixture #{i} to a stable structure" do
      assert Corobook::ChordPro::RoundTrip.stable?(src),
        "unstable round-trip for: #{src.inspect}\n#{Corobook::ChordPro::RoundTrip.diff(src).inspect}"
    end
  end

  def serialize(src)
    Corobook::ChordPro::Serializer.serialize(Corobook::ChordPro::Parser.parse(src))
  end

  test "consecutive chords serialize with no inserted space" do
    assert_equal "[G][D]word", serialize("[G][D]word")
  end

  test "a space between chords is preserved inside text" do
    assert_equal "[G] [D]word", serialize("[G] [D]word")
  end

  test "a chord-only line round-trips to bare brackets with no phantom lyric" do
    assert_equal "[G][C][D]", serialize("[G][C][D]")
  end

  test "leading and trailing spaces survive verbatim" do
    assert_equal "  hola  ", serialize("  hola  ")
  end
end

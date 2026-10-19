require "test_helper"

class Corobook::ChordParseTest < ActiveSupport::TestCase
  def parse(s) = Corobook::Chord.parse(s)

  test "parses a bare major triad" do
    c = parse("G")
    assert_equal "G", c.root
    assert_nil c.accidental
    assert_nil c.quality
    assert_not c.unparsed?
  end

  test "parses a minor seventh" do
    c = parse("Em7")
    assert_equal "E", c.root
    assert_equal "m", c.quality
    assert_equal "7", c.extension
  end

  test "parses a sharp root" do
    c = parse("F#")
    assert_equal "F", c.root
    assert_equal "#", c.accidental
    assert_not c.unparsed?
  end

  test "parses a diminished with the degree symbol" do
    c = parse("C°")
    assert_equal "C", c.root
    assert_equal "°", c.quality
    assert_not c.unparsed?
  end

  test "parses a slash chord" do
    c = parse("Dm/F")
    assert_equal "D", c.root
    assert_equal "m", c.quality
    assert_equal "F", c.bass
  end

  test "parses an extended slash chord" do
    c = parse("Cmaj7/G")
    assert_equal "C", c.root
    assert_equal "maj", c.quality
    assert_equal "7", c.extension
    assert_equal "G", c.bass
  end

  test "marks a nonsensical accidental position as unparsed" do
    assert parse("Fm#").unparsed?
  end

  test "marks garbage as unparsed" do
    assert parse("xyz123").unparsed?
    assert parse("").unparsed?
  end

  test "keeps the source verbatim" do
    assert_equal "Cmaj7/G", parse("Cmaj7/G").to_s
  end
end

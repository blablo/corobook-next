require "test_helper"

class Corobook::MusicianRenderTest < ActiveSupport::TestCase
  setup { @church = Church.create!(name: "Central") }

  def song(source, **attrs)
    @church.songs.create!({ title: "X", chordpro_source: source }.merge(attrs))
  end

  def chords(sections)
    sections.flat_map { |s| s["lines"].flat_map { |l| (l["segments"] || []).filter_map { |seg| seg["chord"] } } }
  end

  test "target key transposes when the source key is known" do
    s = song("{key: G}\n[G]Hola [C]mundo")
    transposed, _capo = Corobook::MusicianRender.new(s, target_key: "A", semitones: 0, follower_capo: nil).call
    assert_equal %w[A D], chords(transposed.sections)
  end

  test "an unknown source key falls back to a raw semitone shift, ignoring target key" do
    s = song("[G]Hola [C]mundo") # no {key}
    render = Corobook::MusicianRender.new(s, target_key: "A", semitones: 2, follower_capo: nil)
    transposed, _capo = render.call
    assert_equal %w[A D], chords(transposed.sections) # used semitones: 2, not the target key
    assert_nil render.displayed_key, "no key badge when the source key is unknown"
  end

  test "the displayed key badge reflects the transposed source key" do
    s = song("{key: G}\n[G]Hola")
    render = Corobook::MusicianRender.new(s, target_key: "A", semitones: 0, follower_capo: nil)
    render.call
    assert_equal "A", render.displayed_key
  end

  test "follower capo overrides the song capo" do
    s = song("{key: G}\n[G]Hola", capo: 2)
    _transposed, capo = Corobook::MusicianRender.new(s, target_key: nil, semitones: 0, follower_capo: 4).call
    assert_equal 4, capo
  end

  test "a nil follower capo inherits the song capo" do
    s = song("{key: G}\n[G]Hola", capo: 2)
    _transposed, capo = Corobook::MusicianRender.new(s, target_key: nil, semitones: 0, follower_capo: nil).call
    assert_equal 2, capo
  end

  test "a follower capo of 0 overrides a nonzero song capo" do
    s = song("{key: G}\n[G]Hola", capo: 3)
    _transposed, capo = Corobook::MusicianRender.new(s, target_key: nil, semitones: 0, follower_capo: 0).call
    assert_equal 0, capo
  end
end

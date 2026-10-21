require "test_helper"

class Corobook::MusicianSetViewTest < ActiveSupport::TestCase
  setup do
    @church = Church.create!(name: "Central")
    @set = @church.service_sets.create!(name: "Domingo")
  end

  test "shows the whole set in order: title + every arrangement-ordered section" do
    song = @church.songs.create!(
      title: "Orden", song_key: "C",
      chordpro_source: "{key: C}\n{sov: Verse 1}\n[C]uno\n{eov}\n{soc: Chorus}\n[G]coro\n{eoc}",
      arrangement: [ "Verse 1", "Chorus", "Chorus" ]
    )
    @set.set_items.create!(position: 0, item_type: "song", song: song)

    rows = Corobook::MusicianSetView.new(@set).rows
    assert_equal :title, rows.first.kind
    labels = rows.select { |r| r.kind == :section }.map { |r| r.section["label"] }
    assert_equal [ "Verse 1", "Chorus", "Chorus" ], labels
  end

  test "includes a chords-only intro but marks it not projected" do
    song = @church.songs.create!(
      title: "Con Intro", song_key: "G",
      chordpro_source: "{key: G}\n{sov: Intro}\n[G] [C] [D]\n{eov}\n{soc: Chorus}\nCantad\n{eoc}",
      arrangement: [ "Intro", "Chorus" ]
    )
    @set.set_items.create!(position: 0, item_type: "song", song: song)

    rows = Corobook::MusicianSetView.new(@set).rows
    intro = rows.find { |r| r.kind == :section && r.section["label"] == "Intro" }
    chorus = rows.find { |r| r.kind == :section && r.section["label"] == "Chorus" }

    assert_not_nil intro, "the chords-only intro must be shown in the full set"
    assert_equal false, intro.projected, "a chords-only section is shown but not a projector stop"
    assert_equal true, chorus.projected
  end

  test "section_index matches LiveFrame's contract (0 = title, i+1 = i-th ordered section)" do
    song = @church.songs.create!(
      title: "Indices", song_key: "C",
      chordpro_source: "{key: C}\n{sov: Verse 1}\n[C]uno\n{eov}\n{soc: Chorus}\n[G]coro\n{eoc}",
      arrangement: [ "Verse 1", "Chorus" ]
    )
    item = @set.set_items.create!(position: 0, item_type: "song", song: song)

    rows = Corobook::MusicianSetView.new(@set).rows.select { |r| r.item_id == item.id }
    assert_equal [ 0, 1, 2 ], rows.map(&:section_index)
    assert_equal [ :title, :section, :section ], rows.map(&:kind)
  end

  test "transposes the whole set to the musician's target key" do
    song = @church.songs.create!(
      title: "Transposed", song_key: "G",
      chordpro_source: "{key: G}\n{soc: Chorus}\n[G]Hola [C]mundo\n{eoc}", arrangement: [ "Chorus" ]
    )
    @set.set_items.create!(position: 0, item_type: "song", song: song)

    rows = Corobook::MusicianSetView.new(@set, target_key: "A").rows
    chorus = rows.find { |r| r.kind == :section }
    chords = (chorus.section["lines"] || []).flat_map { |l| l["segments"] || [] }.filter_map { |s| s["chord"].presence }
    assert_includes chords, "A"
    assert_includes chords, "D"
    assert_not_includes chords, "G"
    assert_equal "A", chorus.displayed_key
  end

  test "a text slide contributes one row per page" do
    slide = @church.text_slides.create!(title: "Aviso", reusable: true,
      pages: [ { "body_markdown" => "uno" }, { "body_markdown" => "dos" } ])
    item = @set.set_items.create!(position: 0, item_type: "text_slide", text_slide: slide)

    rows = Corobook::MusicianSetView.new(@set).rows.select { |r| r.item_id == item.id }
    assert_equal 2, rows.size
    assert_equal [ :slide, :slide ], rows.map(&:kind)
    assert_equal [ 0, 1 ], rows.map(&:section_index)
  end
end

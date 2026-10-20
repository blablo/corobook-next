require "test_helper"

class Corobook::LivePositionTest < ActiveSupport::TestCase
  setup do
    @church = Church.create!(name: "Central")
    # A song with two sections.
    @song = @church.songs.create!(title: "Dos secciones",
      chordpro_source: "{sov: V1}\n[G]Linea uno\n{eov}\n{soc}\n[C]Coro\n{eoc}")
    @slide = @church.text_slides.create!(title: "Sermón", reusable: true)
    @set = @church.service_sets.create!(name: "Domingo")
    @i0 = @set.set_items.create!(position: 0, item_type: "song", song: @song)
    @i1 = @set.set_items.create!(position: 1, item_type: "text_slide", text_slide: @slide)
  end

  def pos = Corobook::LivePosition.new(@set)

  test "stops enumerate the song title slide, each song section, then each slide" do
    stops = pos.stops
    # song = 1 title + 2 sections = 3, + slide 1 = 4 stops
    assert_equal 4, stops.length
    assert_equal [ @i0.id, @i0.id, @i0.id, @i1.id ], stops.map(&:set_item_id)
    assert_equal [ 0, 1, 2, 0 ], stops.map(&:section_index)
  end

  test "next advances within a song then crosses into the next item" do
    # 0 = title, 1 = V1, 2 = Coro, then the slide.
    n1 = pos.next_stop(@i0.id, 0)
    assert_equal [ @i0.id, 1 ], [ n1.set_item_id, n1.section_index ]
    n2 = pos.next_stop(@i0.id, 2)
    assert_equal [ @i1.id, 0 ], [ n2.set_item_id, n2.section_index ]
  end

  test "next at the last stop returns nil" do
    assert_nil pos.next_stop(@i1.id, 0)
  end

  test "prev crosses back from an item to the previous item's last section" do
    p1 = pos.prev_stop(@i1.id, 0)
    assert_equal [ @i0.id, 2 ], [ p1.set_item_id, p1.section_index ]
  end

  test "jump goes to the first stop of any item" do
    j = pos.first_stop_of(@i1.id)
    assert_equal [ @i1.id, 0 ], [ j.set_item_id, j.section_index ]
  end

  test "arrangement limits the song's section count (plus the title slide)" do
    @song.update!(arrangement: [ "V1" ]) # only the first verse, + 1 title slide
    assert_equal 2, Corobook::LivePosition.new(@set).section_count_for(@i0)
  end

  test "a multi-page slide contributes one stop per page" do
    @slide.update!(pages: [ { "body_markdown" => "uno" }, { "body_markdown" => "dos" } ])
    p = Corobook::LivePosition.new(@set)
    assert_equal 2, p.section_count_for(@i1)
    # song (title + 2 sections = 3) + 2 slide pages = 5 stops; Next walks page 0 -> page 1 on the slide.
    assert_equal 5, p.stops.length
    n = p.next_stop(@i1.id, 0)
    assert_equal [ @i1.id, 1 ], [ n.set_item_id, n.section_index ]
  end

  test "a chords-only (intro) section is skipped as a stop, keeping later section indices" do
    # Intro = chords, no lyrics; then two real lyric sections.
    song = @church.songs.create!(title: "Con intro",
      chordpro_source: "{sov: Intro}\n[G] [C]\n{eov}\n{sov: V1}\n[G]Uno\n{eov}\n{soc}\nCoro\n{eoc}")
    set = @church.service_sets.create!(name: "X")
    item = set.set_items.create!(position: 0, item_type: "song", song: song)
    p = Corobook::LivePosition.new(set)

    # Title (0) + V1 (2) + Coro (3). The intro at ordered index 0 -> section index 1 is skipped.
    assert_equal [ 0, 2, 3 ], p.stops.select { |s| s.set_item_id == item.id }.map(&:section_index)
    # Advancing from the title lands on V1 (index 2), not the chords-only intro (index 1).
    n = p.next_stop(item.id, 0)
    assert_equal 2, n.section_index
  end
end

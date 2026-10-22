require "test_helper"

# Covers the per-church projector "break by number of lines" pagination: a lyric section is split
# into N-line chunks that reset at the section boundary, each chunk its own projector stop, and
# LiveFrame renders only the current chunk's lines.
class Corobook::ProjectorPaginationTest < ActiveSupport::TestCase
  setup do
    @church = Church.create!(name: "Lines", projector_pagination: "by_lines", projector_lines_per_slide: 2)
    # One section with 3 lyric lines -> ceil(3/2) = 2 chunks.
    @song = @church.songs.create!(title: "Tres lineas",
      chordpro_source: "{sov: V1}\nLinea uno\nLinea dos\nLinea tres\n{eov}")
    @set = @church.service_sets.create!(name: "Domingo")
    @item = @set.set_items.create!(position: 0, item_type: "song", song: @song)
  end

  def pos = Corobook::LivePosition.new(@set)

  test "a lyric section splits into N-line chunks, each a stop with an incrementing chunk_index" do
    stops = pos.stops
    # title (0) + section index 1 chunk 0 + section index 1 chunk 1
    assert_equal 3, stops.length
    assert_equal [ 0, 1, 1 ], stops.map(&:section_index)
    assert_equal [ 0, 0, 1 ], stops.map(&:chunk_index)
  end

  test "next advances through chunks within a section before the section changes" do
    n1 = pos.next_stop(@item.id, 0, 0)          # title -> section 1 chunk 0
    assert_equal [ 1, 0 ], [ n1.section_index, n1.chunk_index ]
    n2 = pos.next_stop(@item.id, 1, 0)          # chunk 0 -> chunk 1
    assert_equal [ 1, 1 ], [ n2.section_index, n2.chunk_index ]
    assert_nil pos.next_stop(@item.id, 1, 1)    # last chunk is the final stop
  end

  test "chunks reset at the section boundary (a new section starts at chunk 0)" do
    @song.update!(chordpro_source:
      "{sov: V1}\nUno\nDos\nTres\n{eov}\n{soc}\nCoroUno\nCoroDos\n{eoc}")
    stops = Corobook::LivePosition.new(@set).stops
    # title + V1(3 lines -> 2 chunks) + Chorus(2 lines -> 1 chunk)
    assert_equal [ [ 0, 0 ], [ 1, 0 ], [ 1, 1 ], [ 2, 0 ] ],
      stops.map { |s| [ s.section_index, s.chunk_index ] }
  end

  test "LiveFrame renders only the current chunk's lines" do
    session = @church.live_sessions.create!(service_set: @set,
      current_set_item_id: @item.id, current_section_index: 1, current_chunk_index: 0)
    frame = Corobook::LiveFrame.new(session)
    assert_equal [ "Linea uno", "Linea dos" ], frame.current_section_plain_lines
    refute frame.final_chunk?

    session.update!(current_chunk_index: 1)
    frame = Corobook::LiveFrame.new(session)
    assert_equal [ "Linea tres" ], frame.current_section_plain_lines
    assert frame.final_chunk?, "last chunk of the last section is the final chunk"
  end

  test "by_section mode is unchanged: one stop per section, chunk_index 0" do
    @church.update!(projector_pagination: "by_section")
    stops = Corobook::LivePosition.new(@set).stops
    assert_equal 2, stops.length # title + one section
    assert_equal [ 0, 0 ], stops.map(&:chunk_index)
  end
end

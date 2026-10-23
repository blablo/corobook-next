require "test_helper"

# One size per song, never below the church minimum: a section too long to fit at the minimum is
# split onto balanced slides, and the stops (LivePosition) and the lines shown (LiveFrame) agree.
class Corobook::SongSlideSizingTest < ActiveSupport::TestCase
  def lines(count, text = "Linea corta") = Array.new(count) { |i| "#{text} #{i + 1}" }

  setup do
    @church = Church.create!(name: "Sizing")
  end

  test "a section that fits at the minimum size stays one slide" do
    slides = Corobook::SlideChunker.new(@church).slides(lines(6))
    assert_equal [ 6 ], slides.map { |s| s.lines.length }
  end

  test "a section too long for the minimum is split into balanced slides" do
    slides = Corobook::SlideChunker.new(@church).slides(lines(15))
    assert_equal [ 8, 7 ], slides.map { |s| s.lines.length }
    assert_equal [ 0, 8 ], slides.map(&:offset)
  end

  test "a larger minimum splits sooner" do
    @church.update!(projector_min_font_size: 10)
    slides = Corobook::SlideChunker.new(@church).slides(lines(8))
    assert_equal [ 4, 4 ], slides.map { |s| s.lines.length }
  end

  test "long lines count as the rows they wrap onto" do
    long = "una linea muy larga que no cabe en un solo renglon de la pantalla cuando el texto es grande"
    chunker = Corobook::SlideChunker.new(@church)
    assert chunker.fits?(lines(8), 5)
    assert_not chunker.fits?(Array.new(8) { long }, 5)
  end

  test "number-of-lines pagination keeps its fixed N-line slides" do
    @church.update!(projector_pagination: "by_lines", projector_lines_per_slide: 4)
    slides = Corobook::SlideChunker.new(@church).slides(lines(15))
    assert_equal [ 4, 4, 4, 3 ], slides.map { |s| s.lines.length }
  end

  test "a trailing blank line never becomes an empty slide of its own" do
    @church.update!(projector_pagination: "by_lines", projector_lines_per_slide: 2)
    slides = Corobook::SlideChunker.new(@church).slides(lines(4) + [ "" ])
    assert_equal [ 2, 2 ], slides.map { |s| s.lines.length }
  end

  test "the minimum cannot be larger than the preferred size" do
    @church.projector_font_size = 6
    @church.projector_min_font_size = 8
    assert_not @church.valid?
    assert @church.errors[:projector_min_font_size].any?
  end

  test "stops and the projector frame agree on a split section" do
    song = @church.songs.create!(title: "Larga", chordpro_source: "{sov: V1}\n#{lines(15).join("\n")}\n{eov}")
    set = @church.service_sets.create!(name: "Domingo")
    item = set.set_items.create!(position: 0, item_type: "song", song: song)

    stops = Corobook::LivePosition.new(set).stops
    assert_equal [ [ 0, 0 ], [ 1, 0 ], [ 1, 1 ] ], stops.map { |s| [ s.section_index, s.chunk_index ] }

    session = @church.live_sessions.create!(service_set: set,
      current_set_item_id: item.id, current_section_index: 1, current_chunk_index: 1)
    frame = Corobook::LiveFrame.new(session)
    assert_equal lines(15).last(7), frame.current_section_plain_lines
    assert frame.final_chunk?
    assert_equal [ 8, 7 ], frame.song_slide_lines.map(&:length)
  end

  test "the projector frame carries the song sizing data and a hidden copy of every slide" do
    @church.update!(projector_font_size: 12, projector_min_font_size: 6)
    song = @church.songs.create!(title: "Dos", chordpro_source: "{sov: V1}\nUno\n{eov}\n{soc}\nCoro\n{eoc}")
    set = @church.service_sets.create!(name: "Domingo")
    item = set.set_items.create!(position: 0, item_type: "song", song: song)
    session = @church.live_sessions.create!(service_set: set,
      current_set_item_id: item.id, current_section_index: 1, current_chunk_index: 0)

    html = ApplicationController.render(partial: "live/projector_frame", locals: { session: session })
    assert_includes html, %(data-fit-fixed-value="12")
    assert_includes html, %(data-fit-min-pct-value="6")
    assert_includes html, %(data-fit-song-key-value="#{song.id}-)
    assert_equal 2, html.scan('data-role="fit-measure-slide"').length
  end
end

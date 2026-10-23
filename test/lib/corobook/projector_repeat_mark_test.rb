require "test_helper"

# A {comment: ×2} after a block (the legacy "//...//" repeat) shows as a small "×2" after the
# block's last line on the projector, including when the section is split into N-line chunks.
class Corobook::ProjectorRepeatMarkTest < ActiveSupport::TestCase
  T = Corobook::ChordPro::Transform

  def section_of(source)
    Corobook::ChordPro::Parser.parse(source).sections.first
  end

  test "a repeat comment marks the last lyric line before it, normalised to ×N" do
    section = section_of("{sov: V1}\nUno\nDos\n{comment: ×2}\nTres\n\n{comment: 3x}\n{eov}")
    assert_equal({ 1 => "×2", 2 => "×3" }, T.section_repeat_marks(section))
  end

  test "ordinary comments are not repeat marks" do
    section = section_of("{sov: V1}\nUno\n{comment: Violin}\n{eov}")
    assert_empty T.section_repeat_marks(section)
  end

  test "the projector renders a small mark after the repeated line" do
    church = Church.create!(name: "Rep")
    song = church.songs.create!(title: "Rep", chordpro_source: "{sov: V1}\nUno\nDos\n{comment: ×2}\n{eov}")
    html = ApplicationController.render(partial: "songs/projector_section",
      locals: { section: song.parsed_lyric["sections"].first, is_final_section: false,
                song: song, church_license: nil })
    assert_includes html, %(Dos<span class="projector-repeat" data-role="repeat-mark">×2</span>)
    refute_includes html, "Uno<span"
  end

  test "in by_lines mode each chunk gets only its own marks, re-indexed to the slide" do
    church = Church.create!(name: "Lines", projector_pagination: "by_lines", projector_lines_per_slide: 2)
    song = church.songs.create!(title: "Tres",
      chordpro_source: "{sov: V1}\nUno\nDos\nTres\n{comment: ×2}\n{eov}")
    set = church.service_sets.create!(name: "Domingo")
    item = set.set_items.create!(position: 0, item_type: "song", song: song)
    session = church.live_sessions.create!(service_set: set,
      current_set_item_id: item.id, current_section_index: 1, current_chunk_index: 0)

    assert_empty Corobook::LiveFrame.new(session).current_repeat_marks

    session.update!(current_chunk_index: 1)
    frame = Corobook::LiveFrame.new(session)
    assert_equal [ "Tres" ], frame.current_section_plain_lines
    assert_equal({ 0 => "×2" }, frame.current_repeat_marks)
  end
end

module SongsHelper
  # Surfaces x_corobook_parse_warning markers the parser attached to sections, for the editor.
  def parse_warnings(song)
    sections = song.parsed_lyric&.dig("sections") || []
    sections.filter_map { |s| s["x_corobook_parse_warning"] }
  end

  # Render a chord-sheet segment's text. Spaces are significant (they space out chords in an
  # intro/instrumental progression), so they must not collapse: escape the text and turn every
  # space into &nbsp;. An empty run gets a single &nbsp; so a chord-only segment keeps width.
  def sheet_segment_text(text)
    return raw("&nbsp;") if text.to_s.empty?

    raw(ERB::Util.html_escape(text).gsub(" ", "&nbsp;"))
  end

  # True when a MusicianSetView row is the one the projector is currently on.
  def musician_current_row?(row, session)
    row.item_id == session.current_set_item_id && row.section_index == session.current_section_index
  end

  # The NEXT projector stop after the current position (what Next will land on), resolved as a
  # MusicianSetView row so the "sneak peek" header matches what the operator will advance to.
  # Returns nil at the end of the set.
  def musician_next_row(rows, session)
    position = Corobook::LivePosition.new(session.service_set)
    nxt = position.next_stop(session.current_set_item_id, session.current_section_index)
    return nil unless nxt

    rows.find { |r| r.item_id == nxt.set_item_id && r.section_index == nxt.section_index }
  end

  # A compact one/two-line preview of a row for the "Next" peek: the section label + first lyric
  # line for a song, the title for a title slide, or the slide title for a slide.
  def musician_row_peek(row)
    case row.kind
    when :title
      content_tag(:span, row.song.title, class: "musician-peek-title")
    when :slide
      content_tag(:span, row.slide.title, class: "musician-peek-title")
    when :section
      label = row.section["label"].presence
      first_line = (row.section["lines"] || []).find { |l| !l["annotation"] }
      text = (first_line&.dig("segments") || []).map { |s| s["text"] }.join.strip
      safe_join([
        (content_tag(:span, label, class: "musician-peek-label") if label),
        (content_tag(:span, text.truncate(60), class: "musician-peek-lyric") if text.present?)
      ].compact, " ")
    end
  end
end

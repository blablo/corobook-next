module SongsHelper
  # Surfaces x_corobook_parse_warning markers the parser attached to sections, for the editor.
  # The lyric line a search matched, so a lyric hit shows why the song is listed. Nil without one.
  def song_snippet(song, query)
    return if query.blank?

    term = query.strip.downcase
    song.plain_text.to_s.lines.map(&:strip).find { |line| line.downcase.include?(term) }
  end

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

  # Render one chord/lyric segment for the musician views (live Now frame, full chart, print).
  # Only the chord plus the first word of its text form an unbreakable anchor (the chord floats
  # in the anchor's own top padding); the rest of the text is plain inline text so a long lyric
  # wraps on a narrow screen instead of overflowing, and every wrapped line that carries a chord
  # reserves its own room above the lyric.
  def musician_segment(seg)
    text = seg["text"].to_s
    chord = seg["chord"].to_s
    anchor = text[/\A\s*\S*/]
    tail = text[anchor.length..]
    anchor_html = anchor.empty? ? raw("&nbsp;") : ERB::Util.html_escape(anchor)

    seg_class = chord.present? ? "musician-seg has-chord" : "musician-seg"
    safe_join([
      content_tag(:span, class: seg_class) do
        safe_join([
          content_tag(:span, chord, class: "musician-chord", data: { role: "chord" }),
          content_tag(:span, anchor_html, class: "musician-text")
        ])
      end,
      # empty?, not present?: a tail of just " " is the space between words and must be kept.
      (content_tag(:span, tail, class: "musician-tail") unless tail.empty?)
    ].compact)
  end

  # True when a MusicianSetView row is the one the projector is currently on.
  def musician_current_row?(row, session)
    row.item_id == session.current_set_item_id && row.section_index == session.current_section_index
  end

  # [label, first lyric] for the stop after the live one ("Way Maker · Chorus", "You are here…"),
  # or nil at the end of the set. Built from the session alone, so the broadcast frame can carry
  # it and the peek follows the projector.
  def musician_next_peek(session)
    nxt = Corobook::LivePosition.new(session.service_set)
            .next_stop(session.current_set_item_id, session.current_section_index, session.current_chunk_index)
    return unless nxt

    peek = session.dup.tap do |s|
      s.assign_attributes(current_set_item_id: nxt.set_item_id, current_section_index: nxt.section_index,
                          current_chunk_index: nxt.chunk_index)
      s.readonly!
    end
    frame = Corobook::LiveFrame.new(peek)
    lyric = frame.current_section_plain_lines.first.to_s.strip if frame.song? && !frame.title_slide? && frame.current_section
    [ operator_stop_label(peek), lyric.presence&.truncate(60) ]
  end
end

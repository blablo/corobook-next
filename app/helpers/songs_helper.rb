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
end

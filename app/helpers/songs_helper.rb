module SongsHelper
  # Surfaces x_corobook_parse_warning markers the parser attached to sections, for the editor.
  def parse_warnings(song)
    sections = song.parsed_lyric&.dig("sections") || []
    sections.filter_map { |s| s["x_corobook_parse_warning"] }
  end
end

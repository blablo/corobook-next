# frozen_string_literal: true

module Corobook
  module Legacy
    # Converts a legacy column-aligned chord/lyric blob (MySQL `songs.lyric`) into ChordPro
    # (design §4.5). Separate from the live parser; runs only during migration. Tolerant: an
    # ambiguous or malformed line is emitted as best-effort text rather than raising.
    #
    # Legacy conventions handled:
    #   * chord line (mostly chord tokens + spaces) sits ABOVE its lyric line; each chord's start
    #     COLUMN maps to a grapheme index in the lyric below → `[chord]` before that grapheme.
    #   * `[VERSE 1]` / `[CHOIR]` / `[BRIDGE]` / `[END]` / `[INTRO]` headers → section directives.
    #   * `//...//` repeat markers → chorus environment ({soc}/{eoc}).
    #   * tabs expanded to spaces before column math; grapheme-column width (not bytes).
    #   * `order` → arrangement; `mood` → x_corobook_mood directive.
    class ChordProConverter
      TAB_WIDTH = 8

      SECTION_MAP = {
        "VERSE" => :verse, "CHOIR" => :chorus, "CHORUS" => :chorus, "CORO" => :chorus,
        "BRIDGE" => :bridge, "PUENTE" => :bridge, "INTRO" => :verse, "END" => :verse, "FINAL" => :verse
      }.freeze

      SECTION_DIRECTIVE = { verse: %w[sov eov], chorus: %w[soc eoc], bridge: %w[sob eob] }.freeze

      # A token that looks like a chord (root + optional accidental/quality/extension/bass).
      CHORD_TOKEN = %r{\A[A-G](?:#|b|♭|♯)?[a-zA-Z0-9°ø+\-/#♭♯()]*\z}

      def self.convert(lyric, order: nil, mood: nil)
        new(lyric, order:, mood:).convert
      end

      def initialize(lyric, order: nil, mood: nil)
        @lyric = lyric.to_s
        @order = order
        @mood = mood
      end

      def convert
        out = []
        out << "{x_corobook_mood: #{@mood}}" if @mood && @mood.to_s != ""

        lines = normalize(@lyric).split("\n", -1)
        emit_lines(lines, out)

        out.join("\n")
      end

      # The arrangement array parsed from the legacy `order` CSV, or nil.
      def arrangement
        return nil if @order.to_s.strip.empty?

        labels = @order.to_s.split(",").map(&:strip).reject(&:empty?)
        labels.empty? ? nil : labels
      end

      private

      def normalize(text)
        text.gsub("\r\n", "\n").gsub("\r", "\n").gsub("\t") { " " * TAB_WIDTH }
      end

      def emit_lines(lines, out)
        i = 0
        while i < lines.length
          line = lines[i]

          if (header = section_header(line))
            open, close = SECTION_DIRECTIVE[header[:kind]]
            out << (header[:label] ? "{#{open}: #{header[:label]}}" : "{#{open}}")
            i += 1
            next
          end

          if chord_line?(line) && i + 1 < lines.length && !chord_line?(lines[i + 1]) && !section_header(lines[i + 1])
            out << merge(line, lines[i + 1])
            i += 2
          else
            out << strip_repeat_markers(line)
            i += 1
          end
        end
      end

      # A `[LABEL]` header or a bare CORO/VERSE line → section kind + optional numbered label.
      def section_header(line)
        s = line.strip
        if (m = /\A\[([A-Za-z]+)(?:\s+(\d+))?\]\z/.match(s))
          kind = SECTION_MAP[m[1].upcase]
          return nil unless kind

          { kind: kind, label: m[2] ? "#{m[1].capitalize} #{m[2]}" : m[1].capitalize }
        elsif (kind = SECTION_MAP[s.upcase]) && s == s.upcase && s.length <= 8
          { kind: kind, label: nil }
        end
      end

      # A line is a chord line if its non-space tokens all look like chords (and there is at least
      # one). Repeat markers // are ignored for the test.
      def chord_line?(line)
        tokens = line.gsub("//", " ").split(/\s+/).reject(&:empty?)
        return false if tokens.empty?

        tokens.all? { |t| CHORD_TOKEN.match?(t) }
      end

      # Map each chord in the chord line to a grapheme index in the lyric line and emit [chord].
      def merge(chord_line, lyric_line)
        placements = chord_positions(chord_line) # [[col, chord], ...]
        graphemes = lyric_line.grapheme_clusters
        result = +""
        col = 0 # running grapheme column of the lyric
        gi = 0
        next_placement = 0

        # Emit any chords that fall before the first grapheme (col 0).
        placements, leading = partition_leading(placements)
        leading.each { |(_c, chord)| result << "[#{chord}]" }

        graphemes.each do
          while next_placement < placements.length && placements[next_placement][0] <= col
            result << "[#{placements[next_placement][1]}]"
            next_placement += 1
          end
          result << graphemes[gi]
          gi += 1
          col += 1
        end
        # Trailing chords past the end of the lyric.
        while next_placement < placements.length
          result << "[#{placements[next_placement][1]}]"
          next_placement += 1
        end

        strip_repeat_markers(result)
      end

      def partition_leading(placements)
        leading = placements.take_while { |(c, _)| c <= 0 }
        [ placements.drop(leading.length), leading ]
      end

      # Column (grapheme index) + chord token for each chord on the chord line.
      def chord_positions(chord_line)
        positions = []
        graphemes = chord_line.grapheme_clusters
        token = +""
        start = nil
        graphemes.each_with_index do |g, idx|
          if g == " "
            positions << [ start, token ] if token != "" && token != "//"
            token = +""
            start = nil
          else
            start ||= idx
            token << g
          end
        end
        positions << [ start, token ] if token != "" && token != "//"
        positions.reject { |(_c, t)| t == "//" }
      end

      def strip_repeat_markers(line)
        line.gsub("//", "").rstrip
      end
    end
  end
end

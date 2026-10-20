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
    #   * `order` → arrangement. `mood` is accepted for signature stability but not emitted
    #     (corobook-next has no mood field; emitting a directive only leaked into the editor).
    class ChordProConverter
      TAB_WIDTH = 8

      SECTION_MAP = {
        "VERSE" => :verse, "VERSO" => :verse, "ESTROFA" => :verse,
        "CHOIR" => :chorus, "CHORUS" => :chorus, "CORO" => :chorus, "ESTRIBILLO" => :chorus,
        "BRIDGE" => :bridge, "PUENTE" => :bridge,
        "PRECORO" => :prechorus, "PRECHORUS" => :prechorus, "PRECHOIR" => :prechorus,
        "PREESTRIBILLO" => :prechorus, "PREBRIDGE" => :prechorus,
        "INTRO" => :verse, "INSTRUMENTAL" => :verse, "SOLO" => :verse, "PUNTOS" => :verse,
        "PARTE" => :verse,
        "OUTRO" => :verse, "END" => :verse, "FINAL" => :verse, "FIN" => :verse
      }.freeze

      SECTION_DIRECTIVE = {
        verse: %w[sov eov], chorus: %w[soc eoc], bridge: %w[sob eob], prechorus: %w[sob eob]
      }.freeze

      # Canonical English section label per base term (the directive kind alone can't tell
      # Intro/Outro/Verse apart — they all serialize to {sov} — so standardize by base word).
      CANONICAL = {
        "VERSE" => "Verse", "VERSO" => "Verse", "ESTROFA" => "Verse",
        "CHOIR" => "Chorus", "CHORUS" => "Chorus", "CORO" => "Chorus", "ESTRIBILLO" => "Chorus",
        "BRIDGE" => "Bridge", "PUENTE" => "Bridge",
        "PRECORO" => "Pre-chorus", "PRECHORUS" => "Pre-chorus", "PRECHOIR" => "Pre-chorus",
        "PREESTRIBILLO" => "Pre-chorus", "PREBRIDGE" => "Pre-chorus",
        "INTRO" => "Intro", "INSTRUMENTAL" => "Instrumental", "SOLO" => "Solo", "PUNTOS" => "Verse",
        "PARTE" => "Verse",
        "OUTRO" => "Outro", "END" => "Outro", "FINAL" => "Outro", "FIN" => "Outro"
      }.freeze

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

        lines = normalize(@lyric).split("\n", -1)
        emit_lines(lines, out)

        out.join("\n")
      end

      # The arrangement array parsed from the legacy `order` CSV, standardized to the same
      # canonical labels the sections use (so play order resolves), or nil.
      def arrangement
        return nil if @order.to_s.strip.empty?

        labels = @order.to_s.split(",").filter_map { |raw| canonical_label(raw.strip) }
        labels.empty? ? nil : labels
      end

      # Map one raw legacy order label (e.g. "VERSO 1", "CORO", "FIN") to its canonical form
      # ("Verse 1", "Chorus", "Outro"). Falls back to a cleaned title-case of the original.
      def canonical_label(raw)
        return nil if raw.empty?

        h = classify_header(raw)
        h ? h[:label] : raw.split(/\s+/).map(&:capitalize).join(" ")
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

      # Parse a `[LABEL]` header (or a bare CORO/VERSE line) into a section kind + optional
      # identifier. Legacy labels are messy: `VERSO 1`, `VERSOA`, `VERSO1`, `CHOIR B`, `VERSE-A`,
      # `VERSE.2`, `PRE CORO`, `CORO FINAL`, plus trailing language tags (`COROES`, `VERSEEN`).
      def section_header(line)
        s = line.strip
        inner =
          if (m = /\A\[(.+)\]\z/.match(s))
            m[1].strip
          elsif s == s.upcase && s.length <= 10 && /\A[A-Za-z]+\z/.match?(s)
            s # a bare one-word header line (e.g. CORO)
          end
        return nil unless inner

        classify_header(inner)
      end

      # Normalize the raw inner label and resolve it to a kind + numbered/lettered label.
      def classify_header(inner)
        # Split into a base word and the rest (identifier): "VERSO 1", "VERSOA", "VERSE.2", "PRE CORO".
        norm = inner.upcase.gsub(/[.\-]/, " ").squeeze(" ").strip
        norm = norm.sub(/\s+(ES|EN)\z/, "") # drop a trailing language tag (spaced)
        # drop a GLUED language tag too (COROES, VERSEEN), but only when a known base remains
        if (m = /\A(.+?)(ES|EN)\z/.match(norm)) && SECTION_MAP.key?(m[1])
          norm = m[1]
        end

        base, ident = split_base_ident(norm)
        return nil if base.nil?

        kind = SECTION_MAP[base]
        return nil unless kind

        # Standardize: canonical English name + a numeric identifier only (drop letter/odd
        # suffixes like "2A", "MACABRO", "G"). A bare header keeps no number.
        name = CANONICAL[base] || base.capitalize
        num = ident.to_s[/\d+/]
        label = num ? "#{name} #{num}" : name
        { kind: kind, label: label }
      end

      # Peel a known base term off the front of a normalized label, returning [base, identifier].
      # Handles "VERSO 1", "VERSOA" (glued letter), "PRE CORO", "CORO FINAL".
      def split_base_ident(norm)
        # Multi-word: first token is the base when it (or first+second) is a known term.
        two = norm.split(" ", 2)
        if two.length == 2 && SECTION_MAP.key?("#{two[0]}#{two[1].split.first}")
          return [ "#{two[0]}#{two[1].split.first}", nil ]
        end
        if two.length == 2 && SECTION_MAP.key?(two[0])
          return [ two[0], two[1] ]
        end

        word = norm.split(" ").first.to_s
        return [ word, nil ] if SECTION_MAP.key?(word)

        # Base term as the LAST word with a leading modifier: "PRIMERA PARTE", "PRE CORO".
        words = norm.split(" ")
        if words.length >= 2 && SECTION_MAP.key?(words.last)
          return [ words.last, words[0...-1].join(" ").capitalize ]
        end

        # Glued suffix like VERSOA / VERSO1 / CHOIRB: strip a trailing letter or digit run.
        if (m = /\A([A-Z]+?)([0-9]+|[A-Z])\z/.match(word)) && SECTION_MAP.key?(m[1])
          return [ m[1], m[2] ]
        end

        [ nil, nil ]
      end

      # A line is a chord line if its non-space tokens all look like chords (and there is at least
      # one). Repeat markers // are ignored for the test.
      def chord_line?(line)
        tokens = line.gsub(%r{/{2,}}, " ").split(/\s+/).reject(&:empty?)
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
        # Legacy repeat wrappers are runs of slashes (// or ///); strip any such run,
        # including a trailing/leading one left by an odd count, without touching a lone
        # slash that is part of a chord token (e.g. D/F#) — those sit inside [brackets] here.
        line.gsub(%r{/{2,}}, "").gsub(%r{(?<![A-Za-z0-9#])/(?![A-Za-z0-9#])}, "").rstrip
      end
    end
  end
end

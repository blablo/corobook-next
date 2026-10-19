# frozen_string_literal: true

module Corobook
  module ChordPro
    # Parses ChordPro source into the versioned ParsedLyric hash (design §4.2, §4.3).
    # Never raises on malformed input — unrecognized tokens are captured verbatim.
    class Parser
      DIRECTIVE = /\A\{\s*([a-zA-Z_]+)\s*(?::\s*(.*?))?\s*\}\z/

      SECTION_OPEN = {
        "start_of_verse" => :verse, "sov" => :verse,
        "start_of_chorus" => :chorus, "soc" => :chorus,
        "start_of_bridge" => :bridge, "sob" => :bridge
      }.freeze

      SECTION_CLOSE = %w[end_of_verse eov end_of_chorus eoc end_of_bridge eob].freeze

      META_KEYS = {
        "title" => "title", "t" => "title",
        "subtitle" => "subtitle", "st" => "subtitle",
        "key" => "key", "capo" => "capo", "transpose" => "transpose"
      }.freeze

      def self.parse(source)
        new(source).parse
      end

      def initialize(source)
        @source = source.to_s
        @meta = {}
        @sections = []
        @current = nil
        @explicit_section = false
      end

      def parse
        normalized = @source.gsub("\r\n", "\n").gsub("\r", "\n")
        normalized.each_line(chomp: true) { |line| consume(line) }
        finalize_open_section
        ParsedLyric.from_hash(build)
      end

      private

      def consume(line)
        if (m = DIRECTIVE.match(line.strip)) && !line.strip.empty?
          handle_directive(m[1].downcase, m[2])
        elsif line.strip.empty?
          handle_blank_line
        else
          ensure_section
          @current[:lines] << parse_line(line)
        end
      end

      def handle_directive(name, value)
        value = value&.strip
        value = nil if value == ""

        if META_KEYS.key?(name)
          @meta[META_KEYS[name]] = cast_meta(META_KEYS[name], value)
        elsif (kind = SECTION_OPEN[name])
          open_section(kind, value)
        elsif SECTION_CLOSE.include?(name)
          finalize_open_section
        elsif %w[comment c].include?(name)
          ensure_section
          @current[:lines] << { "annotation" => value }
        elsif name == "chorus"
          replay_chorus(value)
        end
        # Any other directive is ignored (design §4.3: unknown directives ignored).
      end

      def cast_meta(key, value)
        return value unless %w[capo transpose].include?(key)

        Integer(value, exception: false) || value
      end

      # A blank line only groups sections when NO explicit {so*} directive has been seen
      # (design §4.3 fallback). Once sections are explicit, a blank line is literal content.
      def handle_blank_line
        if @explicit_section
          ensure_section
          @current[:lines] << { "segments" => [ { "text" => "", "chord" => nil } ] }
        elsif @current && !@current[:lines].empty?
          finalize_open_section
        end
      end

      def open_section(kind, label)
        @explicit_section = true
        finalize_open_section
        @current = { label: label, kind: kind, lines: [] }
      end

      def ensure_section
        @current ||= { label: nil, kind: :none, lines: [] }
      end

      def finalize_open_section
        return if @current.nil?

        @sections << @current
        @current = nil
      end

      # Scan a lyric line into chord/text segments. Each [chord] closes the current segment and
      # opens a new one bound to the text that follows (Req 2.1). Mid-word chords work because no
      # word boundary is assumed. A leading no-chord segment is kept only when lead-in text
      # exists, so a line starting with [chord] has no phantom empty segment.
      def parse_line(line)
        segments = []
        current_chord = nil
        buffer = +""

        flush = lambda do
          next if current_chord.nil? && buffer.empty? && !segments.empty?
          next if current_chord.nil? && buffer.empty? && segments.empty? && line.start_with?("[")

          segments << { "text" => buffer, "chord" => current_chord }
        end

        pos = 0
        while pos < line.length
          if line[pos] == "[" && (close = line.index("]", pos))
            flush.call
            current_chord = line[(pos + 1)...close]
            buffer = +""
            pos = close + 1
          else
            buffer << line[pos]
            pos += 1
          end
        end
        flush.call

        segments = [ { "text" => "", "chord" => nil } ] if segments.empty?
        { "segments" => segments }
      end
      def replay_chorus(_label)
        # Implemented in task 3.3b.
      end

      def build
        {
          "version" => ParsedLyric::VERSION,
          "meta" => @meta,
          "sections" => @sections.map { |s|
            {
              "label" => s[:label],
              "kind" => s[:kind].to_s,
              "is_chorus" => s[:kind] == :chorus,
              "lines" => s[:lines]
            }
          }
        }
      end
    end
  end
end

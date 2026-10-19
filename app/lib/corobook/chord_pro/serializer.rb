# frozen_string_literal: true

module Corobook
  module ChordPro
    # ParsedLyric → ChordPro source (design §4.3a). Lyric/chord content is reproduced verbatim;
    # section directives are emitted in canonical form (the round-trip gate re-parses directive
    # lines rather than comparing them byte-for-byte).
    class Serializer
      CANONICAL_OPEN = { "verse" => "sov", "chorus" => "soc", "bridge" => "sob" }.freeze
      CANONICAL_CLOSE = { "verse" => "eov", "chorus" => "eoc", "bridge" => "eob" }.freeze

      def self.serialize(parsed)
        new(parsed).serialize
      end

      def initialize(parsed)
        @parsed = parsed.is_a?(ParsedLyric) ? parsed : ParsedLyric.from_hash(parsed)
      end

      def serialize
        lines = []
        emit_meta(lines)
        @parsed.sections.each { |section| emit_section(lines, section) }
        lines.join("\n")
      end

      private

      def emit_meta(lines)
        meta = @parsed.meta || {}
        lines << "{title: #{meta['title']}}" if meta["title"]
        lines << "{subtitle: #{meta['subtitle']}}" if meta["subtitle"]
        lines << "{key: #{meta['key']}}" if meta["key"]
        lines << "{capo: #{meta['capo']}}" if meta["capo"]
        lines << "{transpose: #{meta['transpose']}}" if meta["transpose"]
      end

      def emit_section(lines, section)
        kind = section["kind"]
        open = CANONICAL_OPEN[kind]

        # A {chorus} replay serializes back to the replay directive, not its expanded lines.
        if section["replay_of"] || (section.key?("replay_of") && kind == "chorus")
          lines << "{chorus}"
          return
        end

        if open
          label = section["label"]
          lines << (label ? "{#{open}: #{label}}" : "{#{open}}")
        end

        section["lines"].each { |line| emit_line(lines, line) }

        close = CANONICAL_CLOSE[kind]
        lines << "{#{close}}" if open && close
      end

      def emit_line(lines, line)
        if line.key?("annotation")
          lines << "{comment: #{line['annotation']}}"
          return
        end

        lines << line["segments"].map { |seg|
          prefix = seg["chord"] ? "[#{seg['chord']}]" : ""
          "#{prefix}#{seg['text']}"
        }.join
      end
    end
  end
end

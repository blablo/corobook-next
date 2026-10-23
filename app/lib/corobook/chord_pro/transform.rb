# frozen_string_literal: true

module Corobook
  module ChordPro
    # Pure transforms over a ParsedLyric (design §4.4, §8). No DB writes. Every view (operator and
    # musician) renders through here server-side; there is no parallel JS transposer.
    module Transform
      module_function

      # Returns a new ParsedLyric with every chord shifted. The song's own meta {transpose}
      # baseline is applied FIRST, then the follower's requested `semitones`, then `capo` is
      # applied as a display shift (−capo). Enharmonic spelling follows `prefer` (default: derived
      # from the song key). Unparsed chords pass through untouched.
      def transpose(parsed, semitones: 0, capo: 0, prefer: nil)
        parsed = ParsedLyric.from_hash(parsed) unless parsed.is_a?(ParsedLyric)
        meta = parsed.meta || {}
        baseline = meta["transpose"].to_i
        total = baseline + semitones.to_i - capo.to_i
        spelling = prefer || Chord.spelling_for(meta["key"])

        data = deep_dup(parsed.to_h)
        data["sections"].each do |section|
          section["lines"].each do |line|
            next unless line["segments"]

            line["segments"].each do |seg|
              next if seg["chord"].nil?

              seg["chord"] = Chord.parse(seg["chord"]).transpose(total, prefer: spelling).to_s
            end
          end
        end
        ParsedLyric.from_hash(data)
      end

      # Lyric text only — chords, directives and annotations stripped. Mid-word segments rejoin
      # into whole words (Req 2.6, §8 search source).
      def plain_text(parsed)
        parsed = ParsedLyric.from_hash(parsed) unless parsed.is_a?(ParsedLyric)
        parsed.sections.flat_map { |section|
          section["lines"].filter_map { |line|
            next unless line["segments"]

            line["segments"].map { |seg| seg["text"] }.join
          }
        }.join("\n")
      end

      def deep_dup(obj)
        Corobook::DeepDup.call(obj)
      end

      # Lyric-only lines for ONE section: chords dropped, ChordPro `//` repeat marks stripped.
      # Used by the projector, which shows words only (Req 3.1).
      def section_plain_lines(section)
        (section["lines"] || []).filter_map do |line|
          next unless line["segments"]

          text = line["segments"].map { |seg| seg["text"] }.join
          text.gsub("//", "").rstrip
        end
      end

      # A {comment} that is only a repeat count: "×2", "x2", "2x", "X 3".
      REPEAT_MARK = /\A\s*(?:[x×]\s*\d+|\d+\s*[x×])\s*\z/i

      # Repeat markers for ONE section, keyed by the index (into section_plain_lines) of the last
      # lyric line of the block being repeated, so the projector can show a small "×2" there.
      # The value is normalised to "×N".
      def section_repeat_marks(section)
        marks = {}
        index = -1
        last_lyric = nil
        (section["lines"] || []).each do |line|
          if line["segments"]
            index += 1
            last_lyric = index unless line["segments"].map { |seg| seg["text"] }.join.strip.empty?
          elsif last_lyric && line["annotation"].to_s.match?(REPEAT_MARK)
            marks[last_lyric] = "×#{line['annotation'][/\d+/]}"
          end
        end
        marks
      end
    end
  end
end

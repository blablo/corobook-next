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
        Marshal.load(Marshal.dump(obj))
      end
    end
  end
end

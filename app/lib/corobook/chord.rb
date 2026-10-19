module Corobook
  # A chord parsed from a ChordPro bracket. Immutable; transpose/capo return new instances.
  # The original string is kept verbatim so an unparsed token round-trips untouched.
  class Chord
    # root | accidental | quality (m, maj, min, dim, aug, °, sus, add, …) | extension | /bass.
    # Built without /x mode because the pattern itself contains '#', which /x would treat as a
    # comment start.
    PATTERN = %r{
      \A
      ([A-G])
      (\#|b|♭|♯)?
      ([a-zA-Z°ø+\-]+)?
      (\d+[a-zA-Z\#b\d]*)?
      (?:/([A-G](?:\#|b|♭|♯)?))?
      \z
    }x

    attr_reader :source, :root, :accidental, :quality, :extension, :bass

    def self.parse(string)
      new(string)
    end

    def initialize(string)
      @source = string.to_s
      m = PATTERN.match(@source)
      if m
        @root = m[1]
        @accidental = normalize_accidental(m[2])
        @quality = m[3]
        @extension = m[4]
        @bass_source = m[5]
        @bass = m[5]
        @unparsed = false
      else
        @unparsed = true
      end
    end

    def unparsed? = @unparsed

    def to_s = @source

    private

    def normalize_accidental(acc)
      case acc
      when "♯" then "#"
      when "♭" then "b"
      else acc
      end
    end
  end
end

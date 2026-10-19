# frozen_string_literal: true

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

    SHARP_NAMES = %w[C C# D D# E F F# G G# A A# B].freeze
    FLAT_NAMES  = %w[C Db D Eb E F Gb G Ab A Bb B].freeze

    # Keys whose signature is written with flats; everything else prefers sharps.
    FLAT_KEYS = %w[F Bb Eb Ab Db Gb Cb Dm Gm Cm Fm Bbm Ebm Abm].freeze

    # Returns a new Chord shifted by `semitones`, keeping quality/extension and transposing the
    # bass too. Enharmonic spelling follows `prefer` (:sharps or :flats). An unparsed chord is
    # returned unchanged (Req 4.4).
    def transpose(semitones, prefer: :sharps)
      return self if unparsed? || semitones.to_i.zero?

      new_root = shift_note(@root, @accidental, semitones, prefer)
      new_bass = @bass ? shift_note(bass_root, bass_accidental, semitones, prefer) : nil

      rebuilt = +new_root
      rebuilt << @quality if @quality
      rebuilt << @extension if @extension
      rebuilt << "/#{new_bass}" if new_bass
      Chord.new(rebuilt)
    end

    # Capo display: a guitarist with a capo on fret n plays shapes sounding n semitones lower,
    # so the displayed chord is the sounding chord transposed DOWN n. Pure display (Req 4.3).
    def capo(frets, prefer: :sharps)
      transpose(-frets.to_i, prefer: prefer)
    end

    # Chooses sharp/flat spelling from a target key's signature.
    def self.spelling_for(key)
      return :sharps if key.nil?

      FLAT_KEYS.include?(key.to_s.strip) ? :flats : :sharps
    end

    # Semitone distance from one key to another, e.g. interval("G", "A") => 2. Returns nil when
    # either key is blank or unrecognized — the caller then offers only a raw semitone shift
    # (Req 4.1: a "target key" needs a known source key).
    def self.interval(from_key, to_key)
      from = key_pitch_class(from_key)
      to = key_pitch_class(to_key)
      return nil if from.nil? || to.nil?

      (to - from) % 12
    end

    def self.key_pitch_class(key)
      return nil if key.nil?

      m = /\A([A-G])(\#|b|♭|♯)?/.match(key.to_s.strip)
      return nil unless m

      new("#{m[1]}#{m[2]}").send(:pitch_class, m[1], (m[2] == "♯" ? "#" : m[2] == "♭" ? "b" : m[2]))
    end

    private

    def pitch_class(note, accidental)
      base = { "C" => 0, "D" => 2, "E" => 4, "F" => 5, "G" => 7, "A" => 9, "B" => 11 }[note]
      base += 1 if accidental == "#"
      base -= 1 if accidental == "b"
      base % 12
    end

    def shift_note(note, accidental, semitones, prefer)
      pc = (pitch_class(note, accidental) + semitones) % 12
      names = prefer == :flats ? FLAT_NAMES : SHARP_NAMES
      names[pc]
    end

    def bass_root = @bass[0]
    def bass_accidental = @bass[1]

    def normalize_accidental(acc)
      case acc
      when "♯" then "#"
      when "♭" then "b"
      else acc
      end
    end
  end
end

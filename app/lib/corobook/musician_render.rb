# frozen_string_literal: true

module Corobook
  # Resolves how a musician follower sees a song: the transpose shift and the effective capo,
  # then renders through Transform (design §4.4, §6.3). Pure; no DB writes.
  #
  # Precedence rules (Req 4.1/4.3/4.7):
  #   * target_key wins over raw semitones when the song's source key is known; if the source key
  #     is unknown, target_key cannot be honored and only a raw semitone shift applies.
  #   * The FOLLOWER's capo choice overrides the song's {capo}. A follower who sets capo nil
  #     inherits the song's {capo}; a follower who sets any capo (including 0) overrides it.
  class MusicianRender
    attr_reader :displayed_key

    def self.call(song, target_key: nil, semitones: 0, follower_capo: nil)
      new(song, target_key:, semitones:, follower_capo:).call
    end

    def initialize(song, target_key:, semitones:, follower_capo:)
      @song = song
      @target_key = target_key.presence
      @semitones = semitones.to_i
      @follower_capo = follower_capo
    end

    def call
      parsed = @song.parsed
      source_key = parsed.meta&.dig("key")

      shift =
        if @target_key && (interval = Chord.interval(source_key, @target_key))
          interval
        else
          @semitones
        end

      capo = effective_capo

      @displayed_key = displayed_key_for(source_key, shift)
      [ Corobook::ChordPro::Transform.transpose(parsed, semitones: shift, capo: capo), capo ]
    end

    # Follower capo overrides the song's {capo}; nil means inherit the song's capo.
    def effective_capo
      return @song.capo.to_i if @follower_capo.nil?

      @follower_capo.to_i
    end

    private

    def displayed_key_for(source_key, shift)
      return nil if source_key.blank?

      spelling = Chord.spelling_for(source_key)
      Chord.parse(source_key).transpose(shift, prefer: spelling).to_s
    end
  end
end

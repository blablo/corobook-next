# frozen_string_literal: true

module Corobook
  # Decides whether a song's copyright notice may be shown on the projector, and composes it
  # (design §7, Req 9.4). A notice is shown ONLY for a copyrighted song whose church has a CCLI
  # license on file; public-domain songs show nothing; anything ambiguous (unknown status or a
  # copyrighted song with no license) is SUPPRESSED and surfaced to the editor instead — never a
  # wrong or guessed notice to the congregation.
  class CopyrightNotice
    Result = Struct.new(:state, :text, :warning, keyword_init: true) do
      def show? = state == :show
      def warn? = state == :warn
    end

    def self.for(song, church_license:)
      new(song, church_license).result
    end

    def initialize(song, church_license)
      @song = song
      @license = church_license.to_s.strip
    end

    def result
      case @song.copyright_status
      when "public_domain"
        Result.new(state: :suppress)
      when "copyrighted"
        if @license.present?
          Result.new(state: :show, text: compose)
        else
          Result.new(state: :warn, warning: "Copyrighted song but the church has no CCLI license on file — notice suppressed.")
        end
      else # unknown
        Result.new(state: :warn, warning: "Copyright status is unknown — classify this song before projecting a notice.")
      end
    end

    private

    def compose
      parts = []
      parts << @song.copyright_line if @song.copyright_line.present?
      parts << "CCLI Song ##{@song.ccli_song_number}" if @song.ccli_song_number.present?
      parts << "Used by Permission. CCLI License ##{@license}"
      parts.join(" · ")
    end
  end
end

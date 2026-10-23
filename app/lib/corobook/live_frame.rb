# frozen_string_literal: true

module Corobook
  # Resolves what a live session is currently showing: the current set item and, for a song, the
  # concrete section at the current section index (honoring arrangement order and replays). Pure.
  class LiveFrame
    attr_reader :session

    def initialize(session)
      @session = session
    end

    def item = session.current_set_item&.item

    def item_type = session.current_set_item&.item_type

    def song? = item_type == "song"

    def text_slide? = item_type == "text_slide"

    # A song shows a TITLE slide at section index 0, then its lyric sections at 1..N.
    def title_slide? = song? && session.current_section_index.zero?

    # The concrete lyric section (JSONB hash) for a song at the current index, or nil.
    # Index 0 is the title slide, so lyric section i lives at session index i + 1.
    def current_section
      current_section_in(item&.parsed_lyric&.dig("sections") || [])
    end

    # Same as current_section but over a supplied sections array (e.g. a transposed lyric's
    # sections), so every follower view resolves the SAME arrangement-ordered section.
    def current_section_in(sections)
      return nil unless song?
      return nil if title_slide?

      ordered_sections_of(sections)[session.current_section_index - 1]
    end

    def ordered_sections
      ordered_sections_of(item&.parsed_lyric&.dig("sections") || [])
    end

    # Resolve a sections array into play order (arrangement-resolved, replays included).
    def ordered_sections_of(sections)
      return [] unless song?

      Corobook::LivePosition.resolve_arrangement(sections, item.arrangement)
    end

    def final_section?
      return true unless song?

      # +1 accounts for the leading title slide at index 0.
      session.current_section_index >= ordered_sections.length
    end

    # The plain lyric lines the projector should show RIGHT NOW: the current slide of the current
    # section (a section may be split onto several slides, see SlideChunker). Returns [] when
    # there is no current song section.
    def current_section_plain_lines(section = current_section)
      current_slide(section)&.lines || []
    end

    # Repeat markers ("×2") for the lines current_section_plain_lines returns, keyed by the
    # line's position on the slide (so each slide of a split section gets only its own markers).
    def current_repeat_marks(section = current_section)
      slide = current_slide(section)
      return {} unless slide

      marks = Corobook::ChordPro::Transform.section_repeat_marks(section)
      marks.filter_map { |i, mark| [ i - slide.offset, mark ] if i >= slide.offset && i < slide.offset + slide.lines.length }.to_h
    end

    # True when the current slide is the LAST slide of the LAST section — i.e. the copyright
    # notice should show.
    def final_chunk?
      return final_section? unless song?
      return false unless final_section?

      section = current_section
      return true unless section

      session.current_chunk_index >= slides_of(section).length - 1
    end

    # The lines of EVERY lyric slide of the current song, in play order. The projector measures
    # them all once so one text size is used for the whole song.
    def song_slide_lines
      return [] unless song?

      ordered_sections
        .reject { |section| Corobook::LivePosition.chords_only_section?(section) }
        .flat_map { |section| slides_of(section).map(&:lines) }
    end

    private

    def current_slide(section)
      return nil unless section

      slides_of(section)[session.current_chunk_index]
    end

    def slides_of(section)
      @chunker ||= Corobook::SlideChunker.new(session.church)
      @chunker.slides(Corobook::ChordPro::Transform.section_plain_lines(section))
    end
  end
end

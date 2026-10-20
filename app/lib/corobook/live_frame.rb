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

      arrangement = item.arrangement
      return sections if arrangement.blank?

      by_label = sections.group_by { |s| s["label"] }
      arrangement.filter_map { |label| by_label[label]&.shift }
    end

    def final_section?
      return true unless song?

      # +1 accounts for the leading title slide at index 0.
      session.current_section_index >= ordered_sections.length
    end
  end
end

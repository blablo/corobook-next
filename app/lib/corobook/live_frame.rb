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

    # The concrete section (JSONB hash) for a song at the current index, or nil.
    def current_section
      return nil unless song?

      ordered_sections[session.current_section_index]
    end

    def ordered_sections
      return [] unless song?

      sections = item.parsed_lyric&.dig("sections") || []
      arrangement = item.arrangement
      return sections if arrangement.blank?

      by_label = sections.group_by { |s| s["label"] }
      arrangement.filter_map { |label| by_label[label]&.shift }
    end

    def final_section?
      return true unless song?

      session.current_section_index >= ordered_sections.length - 1
    end
  end
end

# frozen_string_literal: true

module Corobook
  # Walks a live session's position across the Set's items and each item's sections (design §6.2).
  # A song's sections follow its `arrangement` order when present (resolving each label to its
  # materialized section, replays included), else natural section order. A text slide is a single
  # stop. Pure over the Set's current items; no DB writes.
  class LivePosition
    Stop = Struct.new(:set_item_id, :section_index, keyword_init: true)

    def initialize(service_set)
      @items = service_set.set_items.order(:position).includes(:song, :text_slide).to_a
    end

    # The flat ordered list of stops across the whole set.
    def stops
      @stops ||= @items.flat_map do |item|
        section_count_for(item).times.map { |i| Stop.new(set_item_id: item.id, section_index: i) }
      end
    end

    def first = stops.first

    def index_of(set_item_id, section_index)
      stops.index { |s| s.set_item_id == set_item_id && s.section_index == section_index }
    end

    def next_stop(set_item_id, section_index)
      i = index_of(set_item_id, section_index)
      return nil if i.nil? || i >= stops.length - 1

      stops[i + 1]
    end

    def prev_stop(set_item_id, section_index)
      i = index_of(set_item_id, section_index)
      return nil if i.nil? || i.zero?

      stops[i - 1]
    end

    # Jump to the FIRST stop of a given item (Req 6.10 jump-to-any-item-in-set).
    def first_stop_of(set_item_id)
      stops.find { |s| s.set_item_id == set_item_id }
    end

    # How many ordered sections an item renders. A song honors its arrangement length when set.
    def section_count_for(item)
      if item.item_type == "song"
        song_section_count(item.song)
      else
        1
      end
    end

    private

    def song_section_count(song)
      sections = song.parsed_lyric&.dig("sections") || []
      arrangement = song.arrangement
      if arrangement.present?
        # Each arrangement entry resolves to one materialized section (missing labels skipped).
        labels = sections.map { |s| s["label"] }
        arrangement.count { |label| labels.include?(label) }.clamp(1, Float::INFINITY).to_i
      else
        [ sections.length, 1 ].max
      end
    end
  end
end

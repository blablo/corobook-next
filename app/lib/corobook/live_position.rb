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

    # The flat ordered list of stops across the whole set. For a song: the title slide (index 0)
    # then each ordered lyric section at index 1..N — but a section with chords and NO lyrics
    # (an intro/instrumental) is NOT a stop, so Next/Back skip it on the operator and projector.
    # The surviving sections keep their original index so LiveFrame still maps index -> section.
    def stops
      @stops ||= @items.flat_map { |item| item_stops(item) }
    end

    def item_stops(item)
      if item.item_type == "song"
        song_stops(item)
      else
        pages = [ item.text_slide&.page_count.to_i, 1 ].max
        pages.times.map { |i| Stop.new(set_item_id: item.id, section_index: i) }
      end
    end

    # Title slide at index 0, then one stop per ordered lyric section at index i+1, skipping
    # any section that carries chords but no lyric text.
    def song_stops(item)
      stops = [ Stop.new(set_item_id: item.id, section_index: 0) ]
      ordered_sections(item.song).each_with_index do |section, i|
        next if chords_only_section?(section)

        stops << Stop.new(set_item_id: item.id, section_index: i + 1)
      end
      stops
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

    # How many ordered stops an item contributes. For a song: the title slide + each ordered
    # lyric section that has lyrics (chords-only sections are skipped), matching #song_stops.
    def section_count_for(item)
      if item.item_type == "song"
        song_stops(item).length
      else
        [ item.text_slide&.page_count.to_i, 1 ].max
      end
    end

    private

    # The song's sections in play order (arrangement-resolved, replays included) — the same
    # ordering LiveFrame uses, so stop indices line up with what gets rendered.
    def ordered_sections(song)
      sections = song.parsed_lyric&.dig("sections") || []
      arrangement = song.arrangement
      return sections if arrangement.blank?

      by_label = sections.group_by { |s| s["label"] }
      arrangement.filter_map { |label| by_label[label]&.shift }
    end

    # True when a section has at least one chord but no lyric text anywhere (an intro /
    # instrumental). Such a section projects as a blank screen, so it is skipped as a stop.
    def chords_only_section?(section)
      lines = section["lines"] || []
      segments = lines.flat_map { |l| l["segments"] || [] }
      return false if segments.empty? # a bare/empty section is not "chords-only"; leave it alone

      has_text = segments.any? { |seg| seg["text"].to_s.strip.present? }
      has_chord = segments.any? { |seg| seg["chord"].present? }
      has_chord && !has_text
    end
  end
end

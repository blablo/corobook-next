# frozen_string_literal: true

module Corobook
  # Builds the WHOLE set as a musician reads it: every item in position order, and for each song
  # every arrangement-ordered section — INCLUDING chords-only intros/instrumentals that the
  # projector skips (a player needs the intro chords even when the screen is blank there).
  #
  # Each song is transposed to THIS musician's chosen key/capo (§6.3), so the entire chart is in
  # their key, not just the live section. Pure; no DB writes.
  #
  # The result is a flat list of rows the view renders top to bottom:
  #   { kind: :title,   item:, song:, item_id:, section_index: 0 }
  #   { kind: :section, item:, song:, item_id:, section_index: n, section: <transposed hash>,
  #                      displayed_key:, projected: bool }
  #   { kind: :slide,   item:, slide:, item_id:, section_index: n, page: n }
  #
  # `projected` is false for a chords-only section (shown to the musician, never a projector stop).
  # `section_index` matches LiveFrame's index contract (0 = title, i+1 = i-th ordered section) so a
  # row can be matched to the live position for "current"/"next" highlighting.
  class MusicianSetView
    Row = Struct.new(:kind, :item_id, :section_index, :song, :slide, :item, :section,
                     :displayed_key, :projected, :page, keyword_init: true)

    def initialize(service_set, target_key: nil, semitones: 0, capo: nil)
      @items = service_set.set_items.order(:position).includes(:song, :text_slide).to_a
      @target_key = target_key
      @semitones = semitones.to_i
      @capo = capo
    end

    # The flat, ordered list of rows for the whole set.
    def rows
      @rows ||= @items.flat_map { |item| rows_for(item) }
    end

    private

    def rows_for(item)
      item.item_type == "song" ? song_rows(item) : slide_rows(item)
    end

    def song_rows(item)
      song = item.song
      return [] if song.nil?

      renderer = MusicianRender.new(song, target_key: @target_key, semitones: @semitones, follower_capo: @capo)
      transposed, _capo = renderer.call
      key = renderer.displayed_key

      out = [ Row.new(kind: :title, item_id: item.id, section_index: 0, song: song, item: item,
                      displayed_key: key) ]

      ordered_sections(transposed.to_h["sections"], song.arrangement).each_with_index do |section, i|
        out << Row.new(
          kind: :section, item_id: item.id, section_index: i + 1, song: song, item: item,
          section: section, displayed_key: key, projected: !chords_only_section?(section)
        )
      end
      out
    end

    def slide_rows(item)
      slide = item.text_slide
      return [] if slide.nil?

      pages = [ slide.page_count.to_i, 1 ].max
      pages.times.map do |i|
        Row.new(kind: :slide, item_id: item.id, section_index: i, slide: slide, item: item, page: i)
      end
    end

    # Arrangement-resolved play order for the WHOLE chart (design §: arrangement controls order and
    # repetition, never visibility). A label named N times renders N times; any section NOT named in
    # the arrangement is appended in natural order so nothing is ever hidden from the musician. No
    # arrangement — or one whose labels match nothing — falls back to natural section order. This
    # deliberately differs from LivePosition's consuming walk: the projector steps stops one at a
    # time, but the musician reads everything.
    def ordered_sections(sections, arrangement)
      sections ||= []
      return sections if arrangement.blank?

      by_label = sections.index_by { |s| s["label"] }
      ordered = arrangement.filter_map { |label| by_label[label] }
      return sections if ordered.empty?

      referenced = arrangement.to_set
      leftovers = sections.reject { |s| referenced.include?(s["label"]) }
      ordered + leftovers
    end

    # A section with a chord but no lyric text anywhere (intro/instrumental): shown to the
    # musician, but never a projector stop.
    def chords_only_section?(section)
      lines = section["lines"] || []
      segments = lines.flat_map { |l| l["segments"] || [] }
      return false if segments.empty?

      segments.any? { |s| s["chord"].present? } && segments.none? { |s| s["text"].to_s.strip.present? }
    end
  end
end

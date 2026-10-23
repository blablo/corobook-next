# frozen_string_literal: true

module Corobook
  # Splits one song section's projector lines into slides. Both LivePosition (which stops exist)
  # and LiveFrame (which lines a stop shows) go through here, so they always agree.
  #
  # * "Number of lines" pagination: fixed N-line chunks, as before.
  # * "Song section" pagination: one slide per section, unless the section would not fit even at
  #   the church's minimum size. Then it is split into the fewest balanced slides that do fit
  #   (7 lines -> 4 + 3, never 6 + 1).
  #
  # Whether text fits is estimated here, because the slide list has to be known on the server
  # before any screen has drawn it. Sizes are in % of the lyric area's height (the cqh units the
  # projector uses); the browser then picks the actual per-song size (fit_controller.js).
  class SlideChunker
    AREA_WIDTH = 177.0  # lyric area is 16:9, so its width is ~177% of its height
    CHAR_WIDTH = 0.58   # average glyph advance in em for bold sans lyrics (a little generous)
    UPPER_CHAR_WIDTH = 0.70
    LINE_GAP = 0.35     # em between lines (.projector-line + .projector-line)

    Slide = Struct.new(:offset, :lines)

    def initialize(church)
      settings = church&.projector_settings
      @by_lines = church&.paginate_by_lines? || false
      @lines_per_slide = church&.projector_lines_per_slide.to_i.clamp(1, 20)
      @min_size = settings&.min_font_size || ProjectorSettings::DEFAULT_MIN_FONT_SIZE
      @line_height = settings&.line_height || 1.15
      @char_width = settings&.uppercase_lyrics? ? UPPER_CHAR_WIDTH : CHAR_WIDTH
    end

    # The section's slides, each with the index of its first line in section_plain_lines.
    # Trailing blank lines are dropped first so they never become an empty slide of their own.
    def slides(lines)
      last = lines.rindex { |line| line.to_s.strip.present? }
      lines = last ? lines[0..last] : lines
      return [ Slide.new(0, lines) ] if lines.empty?
      return sliced(lines, @lines_per_slide) if @by_lines
      return [ Slide.new(0, lines) ] if fits?(lines, @min_size)

      (2..lines.length).each do |count|
        parts = balanced(lines, count)
        return parts if parts.all? { |s| fits?(s.lines, @min_size) }
      end
      sliced(lines, 1)
    end

    # Estimated: do these lines fit the lyric area at `size` (% of its height)?
    def fits?(lines, size)
      rows = lines.sum do |line|
        width = line.to_s.strip.length * @char_width * size
        [ (width / AREA_WIDTH).ceil, 1 ].max # a line too wide for the screen wraps onto more rows
      end
      height = rows * @line_height * size + [ lines.length - 1, 0 ].max * LINE_GAP * size
      height <= 100
    end

    private

    def sliced(lines, size)
      lines.each_slice(size).with_index.map { |part, i| Slide.new(i * size, part) }
    end

    # `count` slides whose lengths differ by at most one, longer ones first.
    def balanced(lines, count)
      base, extra = lines.length.divmod(count)
      offset = 0
      Array.new(count) do |i|
        length = base + (i < extra ? 1 : 0)
        slide = Slide.new(offset, lines[offset, length])
        offset += length
        slide
      end
    end
  end
end

# frozen_string_literal: true

module Corobook
  # Projector line spacing as a multiple of the font size, the way PowerPoint offers it. It is the
  # whole distance from one line to the next: lyric lines get no extra gap on top of it.
  module LineSpacing
    OPTIONS = %w[1.0 1.15 1.5 2.0].freeze
    DEFAULT = "1.15"
  end
end

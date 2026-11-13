# frozen_string_literal: true

module Corobook
  # Projector font sizes are entered in points, the way PowerPoint and Keynote do it.
  #
  # A PowerPoint slide is a fixed canvas 7.5 in tall (both 16:9 and 4:3), which is 540 pt. When it
  # is projected the canvas scales to the screen, so 40 pt always fills 40/540 of the screen
  # height. Corobook uses the same canvas: a size in pt is rendered as a share of the screen height
  # (cqh units), so it looks the same on the projector, every preview, and next to a PowerPoint deck.
  module FontSize
    SCREEN_HEIGHT_PT = 540

    # Sizes offered in the slide editor and the song-projection settings.
    OPTIONS = [ 20, 24, 28, 32, 36, 40, 44, 48, 54, 60, 66, 72, 80, 88, 96, 108, 120, 132 ].freeze

    RANGE = 10..200

    # A size in pt as a % of the screen height.
    def self.to_percent(pt) = pt.to_f * 100 / SCREEN_HEIGHT_PT
  end
end

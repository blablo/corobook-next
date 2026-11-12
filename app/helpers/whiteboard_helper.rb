module WhiteboardHelper
  LABELS = %w[idle board slide blanked ended connecting unavailable stop_board stop_slide hint_idle
              hint_board hint_slide banner_board banner_slide clear_confirm].freeze

  # The texts whiteboard_controller.js switches between, in the page's language.
  def whiteboard_labels = LABELS.index_with { |key| t("live.whiteboard.#{key}") }.to_json

  # Pen colours with their names (for screen readers), in toolbar order.
  def whiteboard_colors
    Corobook::Whiteboard::COLORS.zip(%w[black white blue red green yellow])
                                .map { |hex, name| [ hex, t("live.whiteboard.colors.#{name}") ] }
  end
end

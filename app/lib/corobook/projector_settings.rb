# frozen_string_literal: true

module Corobook
  # Turns a church's projector_* columns into the CSS custom properties, modifier classes, and
  # text-casing the projector/operator-preview frame consumes. Pure, read-only over the church.
  #
  # Casing is applied as a CSS `text-transform` (never mutating stored lyrics), so toggling it
  # off is lossless and author names are never permanently upcased.
  class ProjectorSettings
    FONT_STACKS = {
      "sans"      => %(-apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif),
      "serif"     => %(Georgia, "Times New Roman", Times, serif),
      "condensed" => %("Arial Narrow", "Roboto Condensed", "Helvetica Neue", sans-serif),
      "mono"      => %(ui-monospace, "SF Mono", "Cascadia Code", Menlo, Consolas, monospace)
    }.freeze

    LINE_HEIGHTS = { "tight" => "1.0", "normal" => "1.15", "relaxed" => "1.4" }.freeze

    # Flexbox justify-content for the vertical placement of the lyric block on the stage.
    VALIGNS = { "top" => "flex-start", "center" => "center", "bottom" => "flex-end" }.freeze

    CASE_TRANSFORMS = { "none" => "none", "upper" => "uppercase", "title" => "capitalize" }.freeze

    attr_reader :church

    def initialize(church)
      @church = church
    end

    # The `style="..."` declaration string for #live-frame: all projector CSS vars in one place.
    def style
      vars = {
        "--proj-bg"          => background_css,
        "--proj-text"        => church.projector_text_color,
        "--proj-font"        => FONT_STACKS.fetch(church.projector_font, FONT_STACKS["sans"]),
        "--proj-line-height" => LINE_HEIGHTS.fetch(church.projector_line_height, "1.15"),
        "--proj-weight"      => church.projector_bold ? "700" : "400",
        "--proj-valign"      => VALIGNS.fetch(church.projector_valign, "center"),
        "--proj-lyric-case"  => CASE_TRANSFORMS.fetch(church.projector_lyric_case, "none"),
        "--proj-title-case"  => CASE_TRANSFORMS.fetch(church.projector_title_case, "none")
      }
      vars.map { |k, v| "#{k}: #{v}" }.join("; ")
    end

    # The CSS value for the projector background: a solid colour, or a linear gradient between the
    # two colours at the configured angle. Usable directly as a CSS `background` value.
    def background_css
      if church.projector_bg_type == "gradient"
        "linear-gradient(#{church.projector_bg_gradient_angle}deg, " \
          "#{church.projector_bg_color}, #{church.projector_bg_color2})"
      else
        church.projector_bg_color
      end
    end

    def show_credits? = church.projector_show_credits

    # Preferred song-lyric size as % of screen height, or 0 for "as large as fits".
    def font_size = church.projector_font_size.to_i

    DEFAULT_MIN_FONT_SIZE = 5

    # Smallest song-lyric size (% of screen height) before a section is split onto more slides.
    def min_font_size = church.projector_min_font_size || DEFAULT_MIN_FONT_SIZE

    def line_height = LINE_HEIGHTS.fetch(church.projector_line_height, "1.15").to_f

    def uppercase_lyrics? = church.projector_lyric_case == "upper"

    def lines_per_slide = church.projector_lines_per_slide

    def paginate_by_lines? = church.paginate_by_lines?
  end
end

# frozen_string_literal: true

module Corobook
  # Text slide page markdown -> safe HTML, shared by the projector, the previews, the prints and the
  # editor's live preview so they all render a page the same way.
  #
  # On top of standard markdown (each newline a line break, *italic*, **bold**), `~text~` is SMALL
  # text: references and footnotes, shown at a fraction of the body size and dimmed (.slide-small).
  # It uses commonmarker's subscript extension; `~~text~~` stays strikethrough. Raw HTML is still
  # escaped, so a page cannot inject markup.
  module SlideMarkdown
    OPTIONS = { extension: { subscript: true } }.freeze

    module_function

    def render(markdown)
      html = Commonmarker.to_html(markdown.to_s.encode("UTF-8"), options: OPTIONS)
      SlideCountdown.render(html.gsub("<sub>", %(<sub class="slide-small">)))
    end
  end
end

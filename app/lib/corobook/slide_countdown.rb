module Corobook
  # Countdown fields inside text slide pages. The editor stores each one as a hidden marker in
  # the page markdown, which the author never types:
  #
  #   {{countdown 10:30}}                 until 10:30 on each screen's own clock
  #   {{countdown 10:30 | ¡Comenzamos!}}  ... then show that text at zero
  #   {{countdown 5m}}                    for 5 minutes from when the slide went live
  #
  # After markdown rendering, each marker becomes a live <span> driven by the countdown
  # Stimulus controller. A malformed marker stays as plain text.
  module SlideCountdown
    TOKEN = /\{\{\s*countdown\s+(\d{1,2}:\d{2}|\d{1,3}m)\s*(?:\|\s*([^{}<]*?))?\s*\}\}/

    module_function

    def present?(markdown) = TOKEN.match?(markdown.to_s)

    # Replace markers in rendered (already HTML-escaped) page HTML with live countdown spans.
    def render(html)
      html.to_s.gsub(TOKEN) do
        target = Regexp.last_match(1)
        # The end text arrives HTML-escaped from the markdown renderer; decode it, then escape it
        # again for the attribute so quotes can never break out.
        end_text = CGI.unescapeHTML(Regexp.last_match(2).to_s.strip)
        attrs = { class: "slide-countdown", "data-controller" => "countdown", "data-role" => "countdown",
                  "data-countdown-end-value" => end_text }
        if target.end_with?("m")
          attrs["data-countdown-minutes-value"] = target.delete_suffix("m").to_i
        else
          attrs["data-countdown-to-value"] = target
        end
        attr_html = attrs.map { |k, v| %(#{k}="#{ERB::Util.html_escape(v)}") }.join(" ")
        %(<span #{attr_html}>00:00</span>)
      end
    end
  end
end

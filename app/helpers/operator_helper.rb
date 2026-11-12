module OperatorHelper
  # Heroicons (outline, 24px) used by the operator's join tiles.
  ICON_PATHS = {
    tv: "M6 20.25h12m-7.5-3v3m3-3v3m-10.125-3h17.25c.621 0 1.125-.504 1.125-1.125V4.875c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125v11.25c0 .621.504 1.125 1.125 1.125Z",
    musical_note: "m9 9 10.5-3m0 6.553v3.75a2.25 2.25 0 0 1-1.632 2.163l-1.32.377a1.803 1.803 0 1 1-.99-3.467l2.31-.66a2.25 2.25 0 0 0 1.632-2.163Zm0 0V2.25L9 5.25v10.303m0 0v3.75a2.25 2.25 0 0 1-1.632 2.163l-1.32.377a1.803 1.803 0 0 1-.99-3.467l2.31-.66A2.25 2.25 0 0 0 9 15.553Z",
    microphone: "M12 18.75a6 6 0 0 0 6-6v-1.5m-6 7.5a6 6 0 0 1-6-6v-1.5m6 7.5v3.75m-3.75 0h7.5M12 15.75a3 3 0 0 1-3-3V4.5a3 3 0 1 1 6 0v8.25a3 3 0 0 1-3 3Z",
    link: "M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m13.35-.622 1.757-1.757a4.5 4.5 0 0 0-6.364-6.364l-4.5 4.5a4.5 4.5 0 0 0 1.242 7.244",
    check: "m4.5 12.75 6 6 9-13.5",
    arrows_out: "M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15"
  }.freeze

  def operator_icon(name, css = "size-4")
    tag.svg(xmlns: "http://www.w3.org/2000/svg", class: css, fill: "none", viewBox: "0 0 24 24",
            stroke: "currentColor", "stroke-width": "1.8", "aria-hidden": "true") do
      tag.path("stroke-linecap": "round", "stroke-linejoin": "round", d: ICON_PATHS.fetch(name))
    end
  end
  # A follow link (projector, band view, speaker view) on the host the operator is using, so it
  # works from a church subdomain or the bare domain alike.
  def follow_url(route, token)
    public_send(:"#{route}_url", token, host: request.host_with_port, protocol: request.protocol.delete_suffix("://"))
  end

  # The same label as plain text, for the speaker view and its channel messages. An
  # auto-advancing slide shows only its title, since its pages turn in the browser.
  def stop_label_text(session)
    item = session.current_item
    return item.title if item.is_a?(TextSlide) && item.auto_advance?

    CGI.unescapeHTML(strip_tags(operator_stop_label(session)))
  end

  # "Vamos a Cantar · Chorus" / "Lectura Bíblica · Page 2 of 3": what a (live or preview)
  # session is showing, for the operator's Now / Next labels.
  def operator_stop_label(session)
    item = session.current_item
    return "" unless item

    frame = Corobook::LiveFrame.new(session)
    detail =
      if frame.title_slide?
        t("live.operator.title_slide")
      elsif frame.song?
        section = frame.current_section
        section && (section["label"].presence || section["kind"]&.capitalize)
      elsif frame.text_slide? && item.auto_advance?
        # The page part is kept current in the browser by the auto-page-label controller.
        content_tag(:span, t("live.operator.page", n: 1, count: item.page_count),
                    data: { role: "auto-page-label", "auto-page-label-target": "text" })
      elsif frame.text_slide? && item.page_count > 1
        t("live.operator.page", n: session.current_section_index + 1, count: item.page_count)
      end
    safe_join([ item.title, detail ].compact_blank, " · ")
  end

  # True when the session's current stop is a text slide whose pages turn by themselves.
  def operator_auto_slide?(session)
    session.current_set_item&.item_type == "text_slide" && session.current_item&.auto_advance?
  end

  # "↻ Auto · 8s": tells the operator this slide turns its own pages and Next leaves it.
  def operator_auto_badge(session)
    return unless operator_auto_slide?(session)

    auto_advance_badge(session.current_item)
  end

  # The same badge for one set item (Jump to item list). nil unless it is an auto-advancing slide.
  def set_item_auto_badge(set_item)
    return unless set_item.item_type == "text_slide" && set_item.item&.auto_advance?

    auto_advance_badge(set_item.item)
  end

  # "⏱ 04:37 left" on the Now card when the live slide has a countdown; the browser fills in the
  # time from the slide's own countdown (countdown:tick).
  def operator_countdown_badge(session)
    return unless session.current_set_item&.item_type == "text_slide" && session.current_item&.countdown?

    content_tag(:span, t("live.operator.countdown_badge", t: "--:--"),
                class: "badge badge-info badge-sm", data: {
                  role: "countdown-badge", "auto-page-label-target": "countdown",
                  left: t("live.operator.countdown_badge", t: "%{t}"), done: t("live.operator.countdown_done")
                })
  end

  def auto_advance_badge(slide)
    content_tag(:span, t("live.operator.auto_badge", s: slide.auto_advance_seconds),
                class: "badge badge-info badge-sm", title: t("live.operator.auto_badge_title"),
                data: { role: "auto-badge" })
  end
end

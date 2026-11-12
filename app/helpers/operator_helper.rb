module OperatorHelper
  # "Vamos a Cantar · Chorus" / "Lectura Bíblica · Page 2 of 3": what a (live or preview)
  # session is showing, for the operator's Now / Next labels.
  # A follow link (projector, band view, speaker view) on the host the operator is using, so it
  # works from a church subdomain or the bare domain alike.
  def follow_url(route, token)
    public_send(:"#{route}_url", token, host: request.host_with_port, protocol: request.protocol.delete_suffix("://"))
  end

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

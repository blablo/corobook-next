module OperatorHelper
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
        safe_join([
          content_tag(:span, t("live.operator.page", n: 1, count: item.page_count),
                      data: { role: "auto-page-label", "auto-page-label-target": "text" }),
          t("live.operator.auto")
        ], " · ")
      elsif frame.text_slide? && item.page_count > 1
        t("live.operator.page", n: session.current_section_index + 1, count: item.page_count)
      end
    safe_join([ item.title, detail ].compact_blank, " · ")
  end
end

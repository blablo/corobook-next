module ServiceSetsHelper
  PREVIEW_ITEMS = 4

  # "Way Maker · Oceans · Welcome", the first few item titles of a service.
  def set_items_preview(set)
    titles = set.set_items.filter_map(&:resolved_title)
    preview = titles.first(PREVIEW_ITEMS).join(" · ")
    titles.size > PREVIEW_ITEMS ? "#{preview} …" : preview
  end

  def set_song_count(set) = set.set_items.to_a.count(&:song_id)
  def set_slide_count(set) = set.set_items.to_a.count(&:text_slide_id)

  # "Today", "Tomorrow" or "in 4 days" for an upcoming service date.
  def days_until(date)
    days = (date - Date.current).to_i
    case days
    when 0 then t("services.index.today")
    when 1 then t("services.index.tomorrow")
    else t("services.index.in_days", count: days)
    end
  end
end

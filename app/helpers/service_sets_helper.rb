module ServiceSetsHelper
  PREVIEW_ITEMS = 4

  # "Way Maker · Oceans · Welcome", the first few item titles of a service.
  def set_items_preview(set)
    titles = set.set_items.filter_map(&:resolved_title)
    preview = titles.first(PREVIEW_ITEMS).join(" · ")
    titles.size > PREVIEW_ITEMS ? "#{preview} …" : preview
  end

  # "Song · Stuart K. Hine" or "Slide · 3 pages", the line under an item's title in the program.
  def set_item_subtitle(item)
    if item.item_type == "song"
      [ t("services.item.song"), item.song&.author.presence ].compact.join(" · ")
    else
      pages = item.text_slide&.page_count.to_i
      [ t("services.item.slide"), (t("slides.index.pages", count: pages) if pages > 1) ].compact.join(" · ")
    end
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

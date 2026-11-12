module ServiceSetsHelper
  PREVIEW_ITEMS = 4

  # "Way Maker · Oceans · Welcome", the first few item titles of a service. An empty slot shows
  # its label ("Worship song").
  def set_items_preview(set)
    titles = set.set_items.filter_map { |item| item.resolved_title || item.slot_label }
    preview = titles.first(PREVIEW_ITEMS).join(" · ")
    titles.size > PREVIEW_ITEMS ? "#{preview} …" : preview
  end

  # "9 items · 3 song slots · 4 slide slots" for a template (items: false drops the item count).
  def template_summary(set, items: true)
    all = set.set_items.to_a
    song_slots = all.count { |i| i.slot? && i.song? }
    slide_slots = all.count { |i| i.slot? && i.text_slide? }
    parts = [ (t("services.index.items", count: all.size) if items || (song_slots + slide_slots).zero?),
              (t("services.template.song_slots", count: song_slots) if song_slots.positive?),
              (t("services.template.slide_slots", count: slide_slots) if slide_slots.positive?) ]
    parts.compact.join(" · ")
  end

  # "Choose a song" / "Choose a scripture slide": what an empty slot's button says.
  def slot_choose_label(item)
    return t("services.slots.choose_song") if item.song?

    item.slot_tag ? t("services.slots.choose_tagged_slide", tag: item.slot_tag) : t("services.slots.choose_slide")
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

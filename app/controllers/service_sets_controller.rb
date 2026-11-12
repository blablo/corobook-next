class ServiceSetsController < ApplicationController
  layout "shell"
  before_action :require_sign_in
  before_action :require_editor, except: %i[index show preview print]
  before_action :set_service_set, only: %i[show edit update destroy add_item reorder remove_item fill_item library
                                           preview print send_to_band toggle_default]

  PAST_PER_PAGE = 20
  TABS = %w[upcoming past templates].freeze

  def index
    all_sets = church_scope(:service_sets).includes(set_items: %i[song text_slide])
    sets = all_sets.services
    today = Date.current
    # Upcoming = today or later (plus any set with no date), soonest first.
    upcoming = sets.where("service_date >= ? OR service_date IS NULL", today)
                   .order(Arel.sql("service_date ASC NULLS LAST, name ASC"))
    # Past = before today, newest first, a page at a time.
    past = sets.where("service_date < ?", today).order(service_date: :desc, name: :asc)
    templates = all_sets.templates.order(:name)

    @upcoming_count = upcoming.count
    @past_count = past.count
    @template_count = templates.count
    @active_session = church_scope(:live_sessions).find_by(status: "active")
    @next_set = upcoming.first
    @tab = TABS.include?(params[:tab]) ? params[:tab] : "upcoming"
    @page = [ params[:page].to_i, 1 ].max

    case @tab
    when "past"
      @sets = past.limit(PAST_PER_PAGE).offset((@page - 1) * PAST_PER_PAGE)
      @older_page = @page + 1 if @past_count > @page * PAST_PER_PAGE
    when "templates"
      @sets = templates
    else
      @sets = @next_set ? upcoming.where.not(id: @next_set.id) : upcoming
    end
  end

  def show
    @items = @service_set.ordered_items.to_a
    @active_session = @service_set.live_sessions.find_by(status: "active")
    # Another set in this church that is currently live (a church allows only one at a time).
    @other_live_session = church_scope(:live_sessions).where(status: "active")
                                                      .where.not(service_set_id: @service_set.id).first
    @songs = church_scope(:songs).order(:title)
    @reusable_slides = church_scope(:text_slides).library.order(:title)
    # For the "New slide" modal, which renders the full text_slides/_form editor.
    @new_slide = church_scope(:text_slides).build(reusable: true, pages: [ { "body_markdown" => "" } ])
    @church_slide_tags = church_scope(:text_slides).library.pluck(:tags).flatten.uniq.sort
    # Tags offered for a template's slide slots: the library's plus any already used by a slot.
    @slot_tags = (@church_slide_tags + @items.filter_map(&:slot_tag)).uniq.sort if @service_set.template?
    @band = church_scope(:users).band.order(:email).to_a
  end

  # Email the planned service to every Band member (Team page), one message each.
  def send_to_band
    return redirect_to service_set_path(@service_set) if @service_set.template?

    band = church_scope(:users).band.to_a
    if band.empty?
      return redirect_to service_set_path(@service_set), alert: t("services.send_to_band.no_band")
    end
    if @service_set.set_items.filled.none?
      return redirect_to service_set_path(@service_set), alert: t("services.send_to_band.no_items")
    end

    band.each do |member|
      ServiceSetsMailer.band(@service_set, member, current_user, I18n.locale.to_s).deliver_later
    end
    redirect_to service_set_path(@service_set), notice: t("services.send_to_band.sent", count: band.size)
  end

  # A one-page, read-through of the whole set in order — every song's sections and every slide,
  # like the musician sees it — so an editor can eyeball the whole service before going live.
  # Honors an optional viewer key/capo (same per-viewer transpose as the musician view).
  def preview
    @set_rows = Corobook::MusicianSetView.new(
      @service_set,
      target_key: params[:key], semitones: params[:semitones].to_i, capo: params[:capo].presence
    ).rows
  end

  # A standalone, print-first band chart (its own minimal layout, no admin shell) — a
  # compact one/two-column sheet the band prints or saves as PDF. Same rows + per-viewer
  # transpose as #preview.
  def print
    @set_rows = Corobook::MusicianSetView.new(
      @service_set,
      target_key: params[:key], semitones: params[:semitones].to_i, capo: params[:capo].presence
    ).rows
    render layout: false
  end

  # ?template=1 starts a template (a name, no date). Otherwise a service for next Sunday that
  # starts from the church's default template unless another (or Blank) is chosen.
  def new
    if params[:template].present?
      @service_set = church_scope(:service_sets).build(template: true)
    else
      date = next_sunday
      @service_set = church_scope(:service_sets).build(service_date: date, name: default_set_name(date))
      load_template_choices
    end
  end

  def edit; end

  def create
    @service_set = church_scope(:service_sets).build(service_set_params)
    @service_set.assign_attributes(template: true, service_date: nil) if params.dig(:service_set, :template) == "1"
    source = church_scope(:service_sets).templates.find_by(id: params[:from_template_id]) unless @service_set.template?

    if save_with_items_from(source)
      redirect_to @service_set, notice: t(@service_set.template? ? "services.create.template" : "services.create.service")
    else
      load_template_choices unless @service_set.template?
      render :new, status: :unprocessable_entity
    end
  end

  def update
    attrs = service_set_params
    attrs = attrs.except(:service_date) if @service_set.template?
    if @service_set.update(attrs)
      redirect_to @service_set, notice: t(@service_set.template? ? "services.update.template" : "services.update.service")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    template = @service_set.template?
    @service_set.destroy
    redirect_to service_sets_path(tab: ("templates" if template)),
                notice: t(template ? "services.destroy.template" : "services.destroy.service")
  end

  # Make this template the one the New service form starts from, or stop it being the default.
  def toggle_default
    return redirect_to(@service_set) unless @service_set.template?

    making = !@service_set.default_template?
    current_church.update!(default_template: (@service_set if making))
    redirect_to @service_set, notice: t(making ? "services.default.made" : "services.default.cleared")
  end

  # Append a song, a reusable slide, a new inline one-off slide, or a template slot at the end of
  # the set. Answers JSON (the builder's optimistic path) or redirects (the no-JS fallback).
  def add_item
    position = (@service_set.set_items.maximum(:position) || -1) + 1
    item = @service_set.set_items.create!(position:, **item_attributes)
    respond_to do |format|
      format.json { render json: item_json(item, html: true), status: :created }
      format.html { redirect_to @service_set }
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.json { render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity }
      format.html { redirect_to @service_set, alert: e.record.errors.full_messages.to_sentence }
    end
  end

  # Reorder from an ordered list of set_item ids. Two passes so the unique (set, position) index
  # is never transiently violated: park everyone at high positions, then assign finals.
  #
  # Rejects a STALE list (ids != current membership — an item was added/removed since load) with
  # 409 so the client re-syncs rather than applying an order built against gone/missing items.
  def reorder
    ids = Array(params[:ordered_ids]).map(&:to_i)
    current = @service_set.set_items.pluck(:id)
    if ids.sort != current.sort
      return respond_to do |format|
        format.json { render json: { error: "stale", items: ordered_items_json }, status: :conflict }
        format.html { redirect_to @service_set, alert: "The service changed — reloaded." }
      end
    end

    offset = (@service_set.set_items.maximum(:position) || 0) + 1000
    SetItem.transaction do
      ids.each_with_index { |id, i| @service_set.set_items.where(id:).update_all(position: offset + i) }
      ids.each_with_index { |id, i| @service_set.set_items.where(id:).update_all(position: i) }
    end
    respond_to do |format|
      format.json { head :no_content }
      format.html { redirect_to @service_set }
    end
  end

  def remove_item
    item = @service_set.set_items.find(params[:item_id])
    # An inline one-off slide is owned by this set; reap it with its item. A reusable library
    # slide is only detached (never deleted from the library).
    inline_slide = item.text_slide if item.text_slide && !item.text_slide.reusable?
    item.destroy
    inline_slide&.destroy
    respond_to do |format|
      format.json { head :no_content }
      format.html { redirect_to @service_set }
    end
  end

  # Fill (or change) a slot with a song, or a library slide, of the slot's kind.
  def fill_item
    item = @service_set.set_items.find(params[:item_id])
    raise ActiveRecord::RecordNotFound unless item.slot?

    if item.song?
      item.update!(song: find_in_church(:songs, params[:song_id]))
    else
      item.update!(text_slide: church_scope(:text_slides).library.find(params[:text_slide_id]))
    end
    respond_to do |format|
      format.json { render json: item_json(item, html: true) }
      format.html { redirect_to @service_set }
    end
  end

  # Picker search (editors only): church-scoped songs or reusable slides, capped at 20.
  def library
    render json: library_rows
  end

  private

  def load_template_choices
    @templates = church_scope(:service_sets).templates.order(:name).to_a
    chosen = params[:from_template_id] || current_church.default_template_id
    @from_template_id = chosen.to_i if @templates.any? { |t| t.id == chosen.to_i }
  end

  # Save the new set and, for a service started from a template, copy the template's items; all
  # or nothing.
  def save_with_items_from(source)
    ServiceSet.transaction do
      raise ActiveRecord::Rollback unless @service_set.save

      @service_set.copy_items_from(source) if source
      true
    end
  end

  # The next Sunday on or after today (today if today is Sunday).
  def next_sunday(from = Date.current)
    from + ((7 - from.wday) % 7)
  end

  # Default set name derived from a service date, e.g. "Sunday, Oct 26".
  def default_set_name(date)
    date&.strftime("%A, %b %-d")
  end

  # Attributes for a new set item from the add_item params; church-scoped lookups keep tenancy.
  def item_attributes
    case params[:kind]
    when "text_slide"
      { item_type: "text_slide", text_slide: find_in_church(:text_slides, params[:text_slide_id]) }
    when "inline_slide"
      slide = church_scope(:text_slides).create!(
        title: params[:title],
        tags: Array(params[:tags]).map { |t| t.to_s.strip }.reject(&:empty?).uniq,
        pages: [ { "body_markdown" => params[:body_markdown].to_s } ],
        reusable: false, set_id: @service_set.id
      )
      { item_type: "text_slide", text_slide: slide }
    when "song_slot"
      { item_type: "song", slot_label: params[:slot_label].presence || t("services.slots.song_label") }
    when "slide_slot"
      tag = params[:slot_tag].to_s.strip.downcase
      raise ActionController::BadRequest, "a slide slot needs a tag" if tag.empty?

      { item_type: "text_slide", slot_tag: tag, slot_label: params[:slot_label].presence || tag.tr("_-", "  ").humanize }
    else
      { item_type: "song", song: find_in_church(:songs, params[:song_id]) }
    end
  end

  def item_json(item, html: false)
    json = {
      id: item.id, kind: item.item_type, title: item.resolved_title,
      subtitle: helpers.set_item_subtitle(item),
      key: (item.song&.song_key if item.item_type == "song"), missing: item.missing?,
      slot_label: item.slot_label, slot_tag: item.slot_tag, empty_slot: item.empty_slot?
    }
    json[:html] = item_row_html(item) if html
    json
  end

  def ordered_items_json
    @service_set.ordered_items.map { |i| item_json(i, html: true) }
  end

  # The program row, rendered by the same partial as the page, so rows added or filled without a
  # reload look exactly like the rest.
  def item_row_html(item)
    @items ||= @service_set.ordered_items.to_a
    index = @items.index { |i| i.id == item.id } || @items.size
    render_to_string(partial: "service_sets/set_item_row", formats: [ :html ],
                     locals: { item:, set: @service_set, index:, count: @items.size, can_edit: true })
  end

  # ≤20 church-scoped matches for the picker; song search covers title/author, slides by title.
  # The slot picker (slot=1) narrows slides to the slot's tag and adds a subtitle with when each
  # match was last used.
  def library_rows
    if params[:kind] == "slide"
      pattern = "%#{TextSlide.sanitize_sql_like(params[:q].to_s.strip)}%"
      scope = church_scope(:text_slides).library.where("title ILIKE ?", pattern)
      scope = scope.tagged(params[:tag]) if params[:tag].present?
      rows = scope.order(:title).limit(20).map { |s| { id: s.id, kind: "text_slide", title: s.title, record: s } }
    else
      rows = church_scope(:songs).search(params[:q]).order(:title).limit(20)
                                 .map { |s| { id: s.id, kind: "song", title: s.title, key: s.song_key, record: s } }
    end
    add_slot_subtitles(rows) if params[:slot].present?
    rows.each { |row| row.delete(:record) }
  end

  # "Sinach · last used Oct 26" for a song, "2 pages · never used" for a slide.
  def add_slot_subtitles(rows)
    column = params[:kind] == "slide" ? :text_slide_id : :song_id
    used = SetItem.last_service_dates(column, rows.map { |r| r[:id] })
    rows.each do |row|
      record = row[:record]
      detail = if column == :song_id
        record.author.presence
      elsif record.page_count > 1
        t("slides.index.pages", count: record.page_count)
      end
      row[:subtitle] = [ detail, last_used_label(used[row[:id]]) ].compact.join(" · ")
    end
  end

  def last_used_label(date)
    date ? t("services.slots.last_used", date: date.strftime("%b %-d")) : t("services.slots.never_used")
  end

  def set_service_set
    @service_set = find_in_church(:service_sets, params[:id])
  end

  def service_set_params
    params.require(:service_set).permit(:name, :service_date)
  end
end

class ServiceSetsController < ApplicationController
  layout "shell"
  before_action :require_sign_in
  before_action :require_editor, except: %i[index show preview]
  before_action :set_service_set, only: %i[show edit update destroy add_item reorder remove_item library preview]

  def index
    sets = church_scope(:service_sets)
    today = Date.current
    # Upcoming = today or later (plus any set with no date), soonest first.
    @upcoming_sets = sets.where("service_date >= ? OR service_date IS NULL", today)
                         .order(Arel.sql("service_date ASC NULLS LAST, name ASC"))
    # Past = before today, newest first.
    @past_sets = sets.where("service_date < ?", today)
                     .order(service_date: :desc, name: :asc)
    @service_sets = @upcoming_sets + @past_sets
  end

  def show
    @items = @service_set.ordered_items.to_a
    @active_session = @service_set.live_sessions.find_by(status: "active")
    # Another set in this church that is currently live (a church allows only one at a time).
    @other_live_session = church_scope(:live_sessions).where(status: "active")
                                                      .where.not(service_set_id: @service_set.id).first
    @songs = church_scope(:songs).order(:title)
    @reusable_slides = church_scope(:text_slides).where(reusable: true).order(:title)
    # For the "New slide" modal, which renders the full text_slides/_form editor.
    @new_slide = church_scope(:text_slides).build(reusable: true, pages: [ { "body_markdown" => "" } ])
    @church_slide_tags = church_scope(:text_slides).pluck(:tags).flatten.uniq.sort
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

  def new
    date = next_sunday
    @service_set = church_scope(:service_sets).build(service_date: date, name: default_set_name(date))
  end

  def edit; end

  def create
    @service_set = church_scope(:service_sets).build(service_set_params)
    if @service_set.save
      redirect_to @service_set, notice: "Service created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @service_set.update(service_set_params)
      redirect_to @service_set, notice: "Service updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @service_set.destroy
    redirect_to service_sets_path, notice: "Service deleted."
  end

  # Append a song, a reusable slide, or a new inline one-off slide at the end of the set.
  # Answers JSON (the builder's optimistic path) or redirects (the no-JS fallback).
  def add_item
    position = (@service_set.set_items.maximum(:position) || -1) + 1
    item = @service_set.set_items.create!(position:, **item_attributes)
    respond_to do |format|
      format.json { render json: item_json(item), status: :created }
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

  # Picker search (editors only): church-scoped songs or reusable slides, capped at 20.
  def library
    render json: library_rows
  end

  private

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
    else
      { item_type: "song", song: find_in_church(:songs, params[:song_id]) }
    end
  end

  def item_json(item)
    {
      id: item.id, kind: item.item_type, title: item.resolved_title,
      key: (item.song&.song_key if item.item_type == "song"), missing: item.missing?
    }
  end

  def ordered_items_json
    @service_set.ordered_items.map { |i| item_json(i) }
  end

  # ≤20 church-scoped matches for the picker; song search covers title/author, slides by title.
  def library_rows
    if params[:kind] == "slide"
      pattern = "%#{TextSlide.sanitize_sql_like(params[:q].to_s.strip)}%"
      church_scope(:text_slides).where(reusable: true).where("title ILIKE ?", pattern)
        .order(:title).limit(20)
        .map { |s| { id: s.id, kind: "text_slide", title: s.title } }
    else
      church_scope(:songs).search(params[:q]).order(:title).limit(20)
        .map { |s| { id: s.id, kind: "song", title: s.title, key: s.song_key } }
    end
  end

  def set_service_set
    @service_set = find_in_church(:service_sets, params[:id])
  end

  def service_set_params
    params.require(:service_set).permit(:name, :service_date)
  end
end

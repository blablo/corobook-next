class ServiceSetsController < ApplicationController
  layout "shell"
  before_action :require_sign_in
  before_action :require_editor, except: %i[index show]
  before_action :set_service_set, only: %i[show edit update destroy add_item reorder remove_item]

  def index
    @service_sets = church_scope(:service_sets).order(service_date: :desc, name: :asc)
  end

  def show
    @songs = church_scope(:songs).order(:title)
    @reusable_slides = church_scope(:text_slides).where(reusable: true).order(:title)
  end

  def new
    @service_set = church_scope(:service_sets).build
  end

  def edit; end

  def create
    @service_set = church_scope(:service_sets).build(service_set_params)
    if @service_set.save
      redirect_to @service_set, notice: "Set created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @service_set.update(service_set_params)
      redirect_to @service_set, notice: "Set updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @service_set.destroy
    redirect_to service_sets_path, notice: "Set deleted."
  end

  # Append a song, a reusable slide, or a new inline one-off slide at the end of the set.
  def add_item
    position = (@service_set.set_items.maximum(:position) || -1) + 1
    case params[:kind]
    when "song"
      song = find_in_church(:songs, params[:song_id])
      @service_set.set_items.create!(position:, item_type: "song", song:)
    when "text_slide"
      slide = find_in_church(:text_slides, params[:text_slide_id])
      @service_set.set_items.create!(position:, item_type: "text_slide", text_slide: slide)
    when "inline_slide"
      slide = church_scope(:text_slides).create!(
        title: params[:title].presence || "Slide", subtype: params[:subtype].presence || "sermon_point",
        body_markdown: params[:body_markdown], reusable: false, set_id: @service_set.id
      )
      @service_set.set_items.create!(position:, item_type: "text_slide", text_slide: slide)
    end
    redirect_to @service_set
  end

  # Reorder from an ordered list of set_item ids. Two passes so the unique (set, position) index
  # is never transiently violated: park everyone at high positions, then assign finals.
  def reorder
    ids = Array(params[:ordered_ids]).map(&:to_i)
    offset = (@service_set.set_items.maximum(:position) || 0) + 1000
    SetItem.transaction do
      ids.each_with_index do |id, index|
        @service_set.set_items.where(id:).update_all(position: offset + index)
      end
      ids.each_with_index do |id, index|
        @service_set.set_items.where(id:).update_all(position: index)
      end
    end
    redirect_to @service_set
  end

  def remove_item
    item = @service_set.set_items.find(params[:item_id])
    item.destroy
    redirect_to @service_set
  end

  private

  def set_service_set
    @service_set = find_in_church(:service_sets, params[:id])
  end

  def service_set_params
    params.require(:service_set).permit(:name, :service_date)
  end
end

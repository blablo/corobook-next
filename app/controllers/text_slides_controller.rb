class TextSlidesController < ApplicationController
  layout "shell"
  before_action :require_sign_in
  before_action :require_editor, except: %i[index show]
  before_action :set_slide, only: %i[show edit update destroy]

  def index
    @query = params[:q]
    @tag = params[:tag].presence
    scope = church_scope(:text_slides).where(reusable: true)
    scope = scope.tagged(@tag) if @tag
    @text_slides = scope.search(@query).order(:title)
    @church_tags = church_tags
  end

  def show; end

  def new
    @text_slide = church_scope(:text_slides).build(reusable: true, pages: [ { "body_markdown" => "" } ])
    @church_tags = church_tags
  end

  def edit
    @church_tags = church_tags
  end

  def create
    @text_slide = church_scope(:text_slides).build(slide_params.merge(reusable: true))
    if @text_slide.save
      respond_to do |format|
        format.json { render json: { id: @text_slide.id, title: @text_slide.title }, status: :created }
        format.html { redirect_to @text_slide, notice: "Slide created." }
      end
    else
      respond_to do |format|
        format.json { render json: { error: @text_slide.errors.full_messages }, status: :unprocessable_entity }
        format.html { @church_tags = church_tags; render :new, status: :unprocessable_entity }
      end
    end
  end

  def update
    # Explicit removal of the background image (a checkbox in the form).
    @text_slide.background_image.purge if params[:text_slide][:remove_background_image] == "1"

    if @text_slide.update(slide_params)
      redirect_to @text_slide, notice: "Slide updated."
    else
      @church_tags = church_tags
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @text_slide.destroy
    redirect_to text_slides_path, notice: "Slide deleted."
  end

  # Live preview: render one page's markdown to the same safe HTML the projector uses.
  def preview
    render json: { html: Commonmarker.to_html(params[:body_markdown].to_s.encode("UTF-8")) }
  end

  private

  # The church's existing tag vocabulary, for autocomplete + the index filter.
  def church_tags
    church_scope(:text_slides).pluck(:tags).flatten.uniq.sort
  end

  def set_slide
    @text_slide = find_in_church(:text_slides, params[:id])
  end

  def slide_params
    params.require(:text_slide).permit(:title, :background_image, :font_size, tags: [], pages: [ :body_markdown ])
  end
end

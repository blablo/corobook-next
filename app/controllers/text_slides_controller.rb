class TextSlidesController < ApplicationController
  layout "shell"
  before_action :require_sign_in
  before_action :require_editor, except: %i[index show archived]
  before_action :set_slide, only: %i[show edit update destroy archive unarchive]

  def index
    @query = params[:q]
    @tag = params[:tag].presence
    scope = church_scope(:text_slides).library
    scope = scope.tagged(@tag) if @tag
    @text_slides = scope.search(@query).order(:title)
    @church_tags = church_tags
    @archived_count = church_scope(:text_slides).archived.count
  end

  # Archived slides: the only place they are listed. Newest-archived first.
  def archived
    @query = params[:q]
    @text_slides = church_scope(:text_slides).archived.search(@query).order(archived_at: :desc)
  end

  def show; end

  def archive
    @text_slide.archive!
    redirect_to text_slides_path(q: params[:q].presence, tag: params[:tag].presence),
                notice: t("slides.archive.archived", title: @text_slide.title)
  end

  def unarchive
    @text_slide.unarchive!
    redirect_to archived_text_slides_path, notice: t("slides.archive.restored", title: @text_slide.title)
  end

  # Upload a PDF export (Google Slides: File → Download → PDF) to create an image slide.
  def import_form; end

  def import
    slide = Corobook::PdfSlideImporter.call(church: current_church, file: params[:pdf], title: params[:title])
    redirect_to slide, notice: t("slides.import.done", count: slide.page_count)
  rescue Corobook::PdfSlideImporter::Error => e
    flash.now[:alert] = t("slides.import.errors.#{e.key}",
                          max_mb: Corobook::PdfSlideImporter::MAX_BYTES / 1.megabyte,
                          max_pages: Corobook::PdfSlideImporter::MAX_PAGES)
    render :import_form, status: :unprocessable_entity
  end

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
    church_scope(:text_slides).library.pluck(:tags).flatten.uniq.sort
  end

  def set_slide
    @text_slide = find_in_church(:text_slides, params[:id])
  end

  def slide_params
    params.require(:text_slide).permit(:title, :background_image, :font_size, :text_align, :vertical_align,
                                       :bg_type, :bg_color, :bg_color2, :bg_gradient_angle, :text_color, :font,
                                       tags: [], pages: [ :body_markdown ])
  end
end

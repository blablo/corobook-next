class TextSlidesController < ApplicationController
  layout "shell"
  before_action :require_sign_in
  before_action :require_editor, except: %i[index show]
  before_action :set_slide, only: %i[show edit update destroy]

  def index
    @query = params[:q]
    @text_slides = church_scope(:text_slides).where(reusable: true).search(@query).order(:title)
  end

  def show; end

  def new
    @text_slide = church_scope(:text_slides).build(reusable: true, subtype: "statement")
  end

  def edit; end

  def create
    @text_slide = church_scope(:text_slides).build(slide_params.merge(reusable: true))
    if @text_slide.save
      redirect_to @text_slide, notice: "Slide created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @text_slide.update(slide_params)
      redirect_to @text_slide, notice: "Slide updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @text_slide.destroy
    redirect_to text_slides_path, notice: "Slide deleted."
  end

  private

  def set_slide
    @text_slide = find_in_church(:text_slides, params[:id])
  end

  def slide_params
    params.require(:text_slide).permit(:title, :subtype, :body_markdown)
  end
end

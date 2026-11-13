module Api
  module V1
    class TextSlidesController < BaseController
      # GET /api/v1/text_slides?q=
      def index
        slides = church.text_slides.library.search(params[:q]).order(:title).limit(50)
        render json: { text_slides: slides.map { |s| summary(s) } }
      end

      # POST /api/v1/text_slides  { text_slide: { title, tags: [], pages: [{body_markdown}],
      #   font_size (pt on the 540 pt canvas, nil = auto), text_align, vertical_align, font }, dry_run: }
      def create
        slide = church.text_slides.build(slide_params.merge(reusable: true))
        existing = church.text_slides.library.where("lower(title) = ?", slide.title.to_s.strip.downcase).first
        return render json: { error: "duplicate", existing: summary(existing) }, status: :conflict if existing && slide.title.present?
        return render json: { error: "invalid", messages: slide.errors.full_messages }, status: :unprocessable_entity unless slide.valid?
        return render json: { dry_run: true, would_create: summary(slide).merge(pages: slide.pages) } if dry_run?

        slide.save!
        render json: { text_slide: summary(slide) }, status: :created
      end

      # GET /api/v1/text_slides/:id  — full content (pages), to read before an update.
      def show
        render json: { text_slide: detail(church.text_slides.find(params[:id])) }
      end

      # PATCH /api/v1/text_slides/:id  { text_slide: {only the fields to change}, dry_run: }
      # Partial: omitted fields are kept; `pages`, when sent, replaces ALL pages. Renaming onto
      # another library slide's title -> 409.
      def update
        slide = church.text_slides.find(params[:id])
        slide.assign_attributes(slide_params)
        changes = slide.changes.except("updated_at")
        clash = slide.title_changed? && church.text_slides.library.where.not(id: slide.id)
                                              .where("lower(title) = ?", slide.title.to_s.strip.downcase).first
        return render json: { error: "duplicate", existing: summary(clash) }, status: :conflict if clash
        return render json: { error: "invalid", messages: slide.errors.full_messages }, status: :unprocessable_entity unless slide.valid?
        return render json: { dry_run: true, would_change: changes.keys, would_update: detail(slide) } if dry_run?

        slide.save!
        render json: { text_slide: detail(slide), changed: changes.keys }
      end

      private

      def summary(slide)
        { id: slide.id, title: slide.title, tags: slide.tags, page_count: slide.page_count,
          font_size: slide.font_size, text_align: slide.text_align, vertical_align: slide.vertical_align, font: slide.font,
          url: slide.persisted? ? Rails.application.routes.url_helpers.text_slide_url(slide, host: ENV["APP_HOST"].presence || request.host_with_port) : nil }
      end

      def detail(slide) = summary(slide).merge(pages: slide.pages)

      def slide_params
        params.require(:text_slide).permit(:title, :font_size, :text_align, :vertical_align, :font, tags: [], pages: [ :body_markdown ])
      end
    end
  end
end

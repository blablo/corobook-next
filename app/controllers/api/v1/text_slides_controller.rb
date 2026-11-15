module Api
  module V1
    class TextSlidesController < BaseController
      # Settable over the API: everything the slide editor sets except a background image upload.
      LAYOUT = %i[font_size line_height text_align vertical_align font].freeze
      LOOK = %i[bg_type bg_color bg_color2 bg_gradient_angle text_color].freeze
      AUTO = %i[auto_advance auto_advance_seconds auto_advance_loop auto_advance_transition].freeze

      # GET /api/v1/text_slides?q=
      def index
        slides = church.text_slides.library.search(params[:q]).order(:title).limit(50)
        render json: { text_slides: slides.map { |s| summary(s) } }
      end

      # POST /api/v1/text_slides  { text_slide: { title, tags: [], pages: [{body_markdown}], layout,
      #   look and auto-advance fields (docs/import_api.md) }, dry_run: }
      def create
        slide = church.text_slides.build(slide_params.merge(reusable: true))
        existing = church.text_slides.library.where("lower(title) = ?", slide.title.to_s.strip.downcase).first
        return render json: { error: "duplicate", existing: summary(existing) }, status: :conflict if existing && slide.title.present?
        return render_invalid(slide) unless valid_for_api?(slide)
        return render json: { dry_run: true, would_create: detail(slide) } if dry_run?

        slide.save!
        render json: { text_slide: detail(slide) }, status: :created
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
        return render_invalid(slide) unless valid_for_api?(slide)
        return render json: { dry_run: true, would_change: changes.keys, would_update: detail(slide) } if dry_run?

        slide.save!
        render json: { text_slide: detail(slide), changed: changes.keys }
      end

      private

      def summary(slide)
        { id: slide.id, title: slide.title, tags: slide.tags, page_count: slide.page_count,
          url: slide.persisted? ? Rails.application.routes.url_helpers.text_slide_url(slide, host: ENV["APP_HOST"].presence || request.host_with_port) : nil }
      end

      # Everything settable, plus each page as the projector renders it (pages_html), so a caller can
      # check its markdown before saving: line breaks, *italic*, ***bold italic***, ~small~.
      def detail(slide)
        summary(slide).merge(slide.slice(*LAYOUT, *LOOK, :auto_advance_seconds, :auto_advance_loop, :auto_advance_transition).symbolize_keys)
                      .merge(pages: slide.pages, pages_html: slide.page_count.times.map { |i| slide.rendered_html(i) })
      end

      # The model allows bg_type "image" with an uploaded file; the JSON API cannot upload one, so
      # an image background without an existing image would project as nothing.
      def valid_for_api?(slide)
        ok = slide.valid?
        if slide.bg_type == "image" && !slide.background_image.attached?
          slide.errors.add(:bg_type, "image needs a background image; upload it in the slide editor")
          ok = false
        end
        ok
      end

      def render_invalid(slide)
        render json: { error: "invalid", messages: slide.errors.full_messages }, status: :unprocessable_entity
      end

      def slide_params
        params.require(:text_slide).permit(:title, *LAYOUT, *LOOK, *AUTO, tags: [], pages: [ :body_markdown ])
      end
    end
  end
end

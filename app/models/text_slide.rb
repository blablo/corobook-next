class TextSlide < ApplicationRecord
  include ChurchChild

  belongs_to :service_set, foreign_key: :set_id, optional: true, inverse_of: :inline_text_slides

  # Optional projection background image (text slides only; song lyrics use the church's
  # solid/gradient projector background). Stored via ActiveStorage (local disk service).
  has_one_attached :background_image

  # Imported decks (PDF exported from Google Slides / PowerPoint / Keynote): one rendered image per
  # page, in page order. Such a slide has `imported: true` and one empty `pages` entry per image.
  has_many_attached :page_images

  BACKGROUND_IMAGE_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  BACKGROUND_IMAGE_MAX_BYTES = 10.megabytes

  # Fixed font sizes offered in the editor, as a percentage of the screen height. nil = auto (fit).
  FONT_SIZE_OPTIONS = [ 4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 24 ].freeze

  validates :font_size, numericality: { only_integer: true, in: 2..30 }, allow_nil: true

  # Where the text sits on the projector screen (all pages). Defaults: centered both ways.
  TEXT_ALIGN_OPTIONS = %w[left center right].freeze
  VERTICAL_ALIGN_OPTIONS = %w[top center bottom].freeze

  validates :text_align, inclusion: { in: TEXT_ALIGN_OPTIONS }
  validates :vertical_align, inclusion: { in: VERTICAL_ALIGN_OPTIONS }

  # CSS classes that place the text on the stage (see .slide-align-* / .slide-valign-*).
  def alignment_classes = "slide-align-#{text_align} slide-valign-#{vertical_align}"

  # Projection look, the same options as Song projection (Church::*_OPTIONS).
  validates :bg_type, inclusion: { in: Church::BG_TYPE_OPTIONS }
  validates :bg_color, :bg_color2, :text_color,
            format: { with: Church::HEX_COLOR_FORMAT, message: "must be a hex color like #112233" }
  validates :bg_gradient_angle, numericality: { only_integer: true, in: 0..360 }
  validates :font, inclusion: { in: Church::FONT_OPTIONS }

  # The --proj-* CSS variables for the stage this slide is shown on (projector #live-frame or a
  # preview box). Same variables the song look uses, so the frame CSS needs no slide branch.
  def projector_style
    {
      "--proj-bg" => Corobook::ProjectorSettings.background_css(bg_type, bg_color, bg_color2, bg_gradient_angle),
      "--proj-text" => text_color,
      "--proj-font" => Corobook::ProjectorSettings.font_stack(font)
    }.map { |k, v| "#{k}: #{v}" }.join("; ")
  end

  before_validation :normalize_tags_and_pages
  validate :acceptable_background_image

  scope :search, ->(q) {
    next all if q.blank?

    pattern = "%#{sanitize_sql_like(q.to_s.strip)}%"
    where("title ILIKE :p OR tags::text ILIKE :p OR pages::text ILIKE :p", p: pattern)
  }

  # Slides carrying a given tag (case-insensitive; tags are stored lower-cased).
  scope :tagged, ->(tag) { where("tags @> ?", [ tag.to_s.strip.downcase ].to_json) }

  validates :title, presence: true
  # Reusable library slide has no owning set; an inline one-off slide must have one.
  validates :set_id, absence: true, if: :reusable?
  validates :set_id, presence: true, unless: :reusable?

  # One or more ordered pages; a single-page slide is the common case.
  def page_count = pages.length

  def page_markdown(index = 0)
    return "" if pages.empty?

    pages[index.to_i.clamp(0, page_count - 1)]["body_markdown"].to_s
  end

  # Rendered HTML for one page. commonmarker escapes raw HTML, so user markdown cannot inject markup.
  def rendered_html(index = 0)
    Commonmarker.to_html(page_markdown(index).encode("UTF-8"))
  end

  # The rendered image for one page of an imported deck (attachments are created in page order).
  def page_image(index = 0)
    images = page_images_attachments.sort_by(&:id)
    images[index.to_i.clamp(0, [ images.size - 1, 0 ].max)]
  end

  # True when the slide shows its background image: Image mode is chosen and an image is attached.
  def background_image? = bg_type == "image" && background_image.attached?

  private

  # Tags: trimmed, lower-cased, de-duplicated. Pages: array of { "body_markdown" => str }, >= 1.
  def normalize_tags_and_pages
    self.tags = Array(tags).map { |t| t.to_s.strip.downcase }.reject(&:blank?).uniq
    self.pages = Array(pages).map { |p| { "body_markdown" => (p.is_a?(Hash) ? p["body_markdown"] : p).to_s } }
    self.pages = [ { "body_markdown" => "" } ] if pages.empty?
  end

  # Reject a background image that is the wrong type or too large (Req: projection backgrounds).
  def acceptable_background_image
    return unless background_image.attached?

    unless background_image.content_type.in?(BACKGROUND_IMAGE_TYPES)
      errors.add(:background_image, "must be a PNG, JPEG, WebP or GIF image")
    end
    if background_image.byte_size > BACKGROUND_IMAGE_MAX_BYTES
      errors.add(:background_image, "must be 10 MB or smaller")
    end
  end
end

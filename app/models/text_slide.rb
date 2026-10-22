class TextSlide < ApplicationRecord
  include ChurchChild

  belongs_to :service_set, foreign_key: :set_id, optional: true, inverse_of: :inline_text_slides

  # Optional projection background image (text slides only; song lyrics use the church's
  # solid/gradient projector background). Stored via ActiveStorage (local disk service).
  has_one_attached :background_image

  BACKGROUND_IMAGE_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  BACKGROUND_IMAGE_MAX_BYTES = 10.megabytes

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

  # True when a usable projection background image is attached.
  def background_image? = background_image.attached?

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

class TextSlide < ApplicationRecord
  include ChurchChild

  belongs_to :service_set, foreign_key: :set_id, optional: true, inverse_of: :inline_text_slides

  SUBTYPES = %w[statement blessing statement_of_faith question sermon_point scripture announcement].freeze

  enum :subtype, SUBTYPES.index_with(&:itself), validate: true

  scope :search, ->(q) {
    next all if q.blank?

    pattern = "%#{sanitize_sql_like(q.to_s.strip)}%"
    where("title ILIKE :p OR subtype ILIKE :p OR body_markdown ILIKE :p", p: pattern)
  }

  validates :title, presence: true
  # Reusable library slide has no owning set; an inline one-off slide must have one.
  validates :set_id, absence: true, if: :reusable?
  validates :set_id, presence: true, unless: :reusable?

  # Rendered HTML is produced on read, never stored (design §2.1). commonmarker escapes raw HTML
  # by default, so user markdown cannot inject markup.
  def rendered_html
    Commonmarker.to_html(body_markdown.to_s.encode("UTF-8"))
  end

  # CSS class driving subtype-specific styling on projector/musician (design §5).
  def subtype_class
    "slide-#{subtype.tr('_', '-')}"
  end
end

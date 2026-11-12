# The domain concept the UI calls a "Set" (a service's ordered list of items). Named ServiceSet
# because Ruby reserves `Set`; every user-facing label still reads "Set".
class ServiceSet < ApplicationRecord
  include ChurchChild

  has_many :set_items, -> { order(:position) }, dependent: :destroy
  has_many :live_sessions, dependent: :destroy
  # Inline one-off slides owned by this set; reusable library slides are NOT reaped.
  has_many :inline_text_slides,
    -> { where(reusable: false) },
    class_name: "TextSlide", foreign_key: :set_id, dependent: :destroy, inverse_of: :service_set

  validates :name, presence: true

  # A template is built in the same set builder but never goes live or shows among services; new
  # services copy its items (see #copy_items_from).
  scope :services, -> { where(template: false) }
  scope :templates, -> { where(template: true) }

  # Permanent musician link (/m/s/:token): works before, during and after a live session, so it
  # can go out in the band email. View-only, like the per-session musician link.
  before_create { self.musician_token ||= SecureRandom.urlsafe_base64(24) }

  def active_live_session = live_sessions.active.first

  def ordered_items = set_items.includes(:song, :text_slide)

  def default_template? = template? && church.default_template_id == id

  def empty_slot_count = set_items.to_a.count(&:empty_slot?)

  # Append a template's items, in order: songs and library slides are referenced, an inline
  # one-off slide is copied so each service owns (and can edit) its own, and slots come over
  # empty with their label and tag.
  def copy_items_from(template)
    start = (set_items.maximum(:position) || -1) + 1
    template.ordered_items.each_with_index do |item, i|
      slide = item.text_slide
      slide = slide.copy_for(self) if slide && !slide.reusable?
      set_items.create!(position: start + i, item_type: item.item_type, slot_label: item.slot_label,
                        slot_tag: item.slot_tag, song: item.song, text_slide: slide)
    end
  end
end

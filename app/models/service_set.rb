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

  # Permanent musician link (/m/s/:token): works before, during and after a live session, so it
  # can go out in the band email. View-only, like the per-session musician link.
  before_create { self.musician_token ||= SecureRandom.urlsafe_base64(24) }

  def active_live_session = live_sessions.active.first

  def ordered_items = set_items.includes(:song, :text_slide)
end

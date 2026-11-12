class SetItem < ApplicationRecord
  belongs_to :service_set
  belongs_to :song, optional: true
  belongs_to :text_slide, optional: true

  enum :item_type, { song: "song", text_slide: "text_slide" }, validate: true

  # A SLOT is a labelled placeholder from a service template ("Worship song", or "Scripture" for
  # slides tagged `scripture`). item_type says what fills it; it stays empty until someone picks
  # one, and remembers its label/tag after, so it can be changed.
  normalizes :slot_label, with: ->(l) { l.squish.presence }
  normalizes :slot_tag, with: ->(t) { t.strip.downcase.presence }

  scope :filled, -> { where("set_items.song_id IS NOT NULL OR set_items.text_slide_id IS NOT NULL") }

  # The latest service date each song or slide appears in, keyed by id; column is :song_id or
  # :text_slide_id. Templates have no date and are left out.
  def self.last_service_dates(column, ids)
    joins(:service_set).merge(ServiceSet.services).where(column => ids)
                       .group(column).maximum("service_sets.service_date")
  end

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :slot_label, length: { maximum: 60 }
  validate :item_matches_kind
  validate :item_in_same_church

  # The referenced item, whichever type this is.
  def item
    song || text_slide
  end

  # The referenced item's title, or nil when the reference was deleted from the library.
  def resolved_title = item&.title

  def slot? = slot_label.present?
  # Checks the ids, not the records, so lists can count empty slots without loading songs/slides
  # (the FKs are RESTRICT, so a set id always has its record).
  def empty_slot? = slot? && song_id.nil? && text_slide_id.nil?

  # True when a regular item's song/slide no longer exists (a dangling reference the builder
  # renders as a removable "missing" placeholder and treats as not launchable). An empty slot is
  # not missing: it is waiting to be filled.
  def missing? = item.nil? && !slot?

  private

  # A regular item references exactly one song or slide; a slot at most one. Either way the
  # reference matches item_type.
  def item_matches_kind
    present = [ song_id, text_slide_id ].compact.length
    if present > 1 || (present.zero? && !slot?)
      errors.add(:base, "a set item must reference exactly one song or text slide")
    elsif (song? && text_slide_id) || (text_slide? && song_id)
      errors.add(:base, "a #{item_type.humanize.downcase} slot takes a #{item_type.humanize.downcase}")
    end
  end

  # The referenced item must belong to the same church as the owning set (tenant safety).
  def item_in_same_church
    return unless service_set

    referenced = item
    return if referenced.nil? || referenced.church_id == service_set.church_id

    errors.add(:base, "item must belong to the same church as the set")
  end
end

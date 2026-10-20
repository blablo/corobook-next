class SetItem < ApplicationRecord
  belongs_to :service_set
  belongs_to :song, optional: true
  belongs_to :text_slide, optional: true

  enum :item_type, { song: "song", text_slide: "text_slide" }, validate: true

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :exactly_one_item
  validate :item_in_same_church

  # The referenced item, whichever type this is.
  def item
    song || text_slide
  end

  # The referenced item's title, or nil when the reference was deleted from the library.
  def resolved_title = item&.title

  # True when this item's song/slide no longer exists (a dangling reference the builder renders
  # as a removable "missing" placeholder and treats as not launchable).
  def missing? = item.nil?

  private

  def exactly_one_item
    present = [ song_id, text_slide_id ].compact.length
    errors.add(:base, "a set item must reference exactly one song or text slide") unless present == 1
  end

  # The referenced item must belong to the same church as the owning set (tenant safety).
  def item_in_same_church
    return unless service_set

    referenced = item
    return if referenced.nil? || referenced.church_id == service_set.church_id

    errors.add(:base, "item must belong to the same church as the set")
  end
end

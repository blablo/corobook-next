class LiveSession < ApplicationRecord
  # Raised when a church already has an active session and a second launch is attempted.
  class AlreadyLiveError < StandardError; end

  include ChurchChild
  church_parent :service_set

  belongs_to :service_set
  belongs_to :current_set_item, class_name: "SetItem", optional: true

  enum :status, { active: "active", ended: "ended" }, validate: true

  # At most one active session per church (design §3a). The DB enforces it with a partial unique
  # index; this validation gives a clean error on the common (non-racing) path.
  validates :church_id, uniqueness: { conditions: -> { where(status: "active") } }, if: :active?

  # Launch one run of a Set: seed position at its first item, issue follow tokens. The row is the
  # authoritative live state (design §6.1); Cable is only transport. Refuses a second concurrent
  # launch for a church (one active session only).
  def self.launch(service_set)
    first_item = service_set.set_items.order(:position).first
    session = create!(
      church: service_set.church,
      service_set: service_set,
      status: "active",
      current_set_item: first_item,
      current_section_index: 0,
      position_version: 0,
      projector_token: SecureRandom.urlsafe_base64(24),
      musician_token: SecureRandom.urlsafe_base64(24),
      started_at: Time.current
    )
    UsageEvent.capture(live_session: session, song: first_item.song) if first_item&.item_type == "song"
    session
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # Validation (common path) or the partial unique index (race) — a church is already live.
    raise AlreadyLiveError, "#{service_set.church.name} already has an active service"
  end

  def end!
    update!(status: "ended", projector_token: nil, musician_token: nil, ended_at: Time.current)
  end

  def current_item = current_set_item&.item
end

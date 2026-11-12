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
    first_item = service_set.set_items.filled.order(:position).first
    session = create!(
      church: service_set.church,
      service_set: service_set,
      status: "active",
      current_set_item: first_item,
      current_section_index: 0,
      position_version: 0,
      projector_token: SecureRandom.urlsafe_base64(24),
      musician_token: SecureRandom.urlsafe_base64(24),
      speaker_token: SecureRandom.urlsafe_base64(24),
      started_at: Time.current,
      position_changed_at: Time.current
    )
    UsageEvent.capture(live_session: session, song: first_item.song) if first_item&.item_type == "song"
    session
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # Validation (common path) or the partial unique index (race) — a church is already live.
    raise AlreadyLiveError, "#{service_set.church.name} already has an active service"
  end

  def end!
    update!(status: "ended", projector_token: nil, musician_token: nil, speaker_token: nil, ended_at: Time.current)
    # Written directly: the speaker may have switched the whiteboard on since this row was loaded,
    # and update! only writes attributes that changed in memory.
    update_columns(whiteboard_mode: nil)
  end

  # The speaker view link (/s/:token). Sessions launched before the whiteboard existed get one
  # the first time the operator asks for it.
  def speaker_token!
    update_column(:speaker_token, SecureRandom.urlsafe_base64(24)) if speaker_token.blank?
    speaker_token
  end

  # A signed key that lets a screen (projector, operator) watch this session's whiteboard
  # without being able to draw; see WhiteboardChannel.
  def whiteboard_viewer_key
    Rails.application.message_verifier(:whiteboard_viewer).generate(id, purpose: :viewer, expires_in: 1.day)
  end

  def self.whiteboard_viewer_id(key)
    Rails.application.message_verifier(:whiteboard_viewer).verified(key.to_s, purpose: :viewer)
  end

  def whiteboard_on? = whiteboard_mode.present?

  def current_item = current_set_item&.item

  # When the current stop went live: the shared start of an auto-advancing slide's page clock.
  # Older sessions predate the column, so fall back to the launch time.
  def position_since = position_changed_at || started_at || updated_at
end

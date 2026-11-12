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
      projector_token: new_token,
      musician_token: new_token,
      speaker_token: new_token,
      started_at: Time.current,
      position_changed_at: Time.current
    )
    UsageEvent.capture(live_session: session, song: first_item.song) if first_item&.item_type == "song"
    session
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # Validation (common path) or the partial unique index (race) — a church is already live.
    raise AlreadyLiveError, "#{service_set.church.name} already has an active service"
  end

  def self.new_token = SecureRandom.urlsafe_base64(24)

  def end!
    update!(status: "ended", projector_token: nil, musician_token: nil, speaker_token: nil, ended_at: Time.current)
    # Written directly: the speaker may have drawn since this row was loaded, and update! only
    # writes attributes that changed in memory. The drawings aren't needed once it's over.
    update_columns(whiteboard_mode: nil, whiteboard_board: [], whiteboard_slide: [], whiteboard_slide_stop: nil)
  end

  # The speaker view link (/s/:token). The migration gave live sessions one; this covers any it
  # missed. Locked, so two operators opening the page at once agree on the same link.
  def speaker_token!
    return speaker_token if speaker_token.present?

    with_lock { update_column(:speaker_token, self.class.new_token) if speaker_token.blank? }
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

  # Move the live position to a stop (a Corobook::LivePosition stop): bump the version, record
  # CCLI usage when a song comes up, and broadcast to every screen. Shared by the operator, the
  # projector's clicker and the speaker view. Returns false when another driver moved it in the
  # same instant (lock_version); the screens already follow that newer position.
  def move_to!(stop)
    with_lock do
      update!(current_set_item_id: stop.set_item_id, current_section_index: stop.section_index,
              current_chunk_index: stop.chunk_index, position_version: position_version + 1,
              # An auto-advancing slide starts its page clock here.
              position_changed_at: Time.current)
      UsageEvent.capture(live_session: self, song: current_set_item.song) if current_set_item&.item_type == "song"
    end
    Corobook::LiveBroadcast.position(self)
    true
  rescue ActiveRecord::StaleObjectError
    false
  end

  # When the current stop went live: the shared start of an auto-advancing slide's page clock.
  # Older sessions predate the column, so fall back to the launch time.
  def position_since = position_changed_at || started_at || updated_at
end

class UsageEvent < ApplicationRecord
  belongs_to :church
  belongs_to :live_session
  belongs_to :song

  # Capture one usage event the first time a song is shown in a session (design §7). Idempotent via
  # the unique (live_session_id, song_id) index; public-domain songs are not reportable and are
  # skipped. Fields are SNAPSHOT at show-time so a later song edit never rewrites history.
  # Church/live_session are passed explicitly — this runs inside the operator position transaction
  # and must never read Current off-request (§3.2.3).
  def self.capture(live_session:, song:)
    return if song.nil? || song.public_domain?
    return if exists?(live_session_id: live_session.id, song_id: song.id)

    create!(
      church: live_session.church,
      live_session: live_session,
      song: song,
      ccli_song_number: song.ccli_song_number,
      title: song.title,
      author: song.author,
      copyright_status: song.copyright_status,
      shown_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    # A concurrent capture won the race; the unique index still guarantees one per song/session.
    nil
  end
end

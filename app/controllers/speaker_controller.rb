# Speaker view: the pastor's tablet. Shows what the projector shows, moves the service with
# Next and Back, and lets him put a whiteboard over it or draw on the current slide. Public like
# the projector: access is gated by the per-session speaker token, which ending the service
# revokes.
class SpeakerController < ApplicationController
  include LiveDriving

  skip_before_action :set_current_user, raise: false
  # Next/Back are token-gated fetches like the projector's clicker, so they skip the session
  # CSRF token the same way.
  skip_before_action :verify_authenticity_token, only: %i[advance back], raise: false
  layout "follower"

  def show
    @session = find_session!
  end

  private

  def find_session!
    LiveSession.active.find_by!(speaker_token: params[:token])
  rescue ActiveRecord::RecordNotFound
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    nil
  end
end

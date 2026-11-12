# Speaker view: the pastor's tablet. Shows what the projector shows and lets him put a whiteboard
# over it or draw on the current slide. Public like the projector: access is gated by the
# per-session speaker token, which ending the service revokes.
class SpeakerController < ApplicationController
  skip_before_action :set_current_user, raise: false
  layout "follower"

  def show
    @session = LiveSession.active.find_by!(speaker_token: params[:token])
  rescue ActiveRecord::RecordNotFound
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end

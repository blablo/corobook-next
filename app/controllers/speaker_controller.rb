# Speaker view: the pastor's tablet. Shows what the projector shows, moves the service with
# Next and Back (LiveDriving), and lets him put a whiteboard over it or draw on the current
# slide. Public like the projector: access is gated by the per-session speaker token, which
# ending the service revokes.
class SpeakerController < ApplicationController
  include LiveDriving
  driven_by :speaker_token

  skip_before_action :set_current_user, raise: false
  layout "follower"

  def show
    @session = find_session!
  end
end

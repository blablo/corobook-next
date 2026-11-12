class ProjectorController < ApplicationController
  include LiveDriving
  # A presentation clicker plugged into the projection machine sends key events to this page,
  # which become Next/Back (LiveDriving).
  driven_by :projector_token

  # Public follower view — no sign-in. Access is gated solely by possession of a valid token.
  skip_before_action :set_current_user, raise: false
  layout "follower"

  def show
    @session = find_session!
  end
end

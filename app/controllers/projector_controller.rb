class ProjectorController < ApplicationController
  include LiveDriving

  # Public follower view — no sign-in. Access is gated solely by possession of a valid token.
  skip_before_action :set_current_user, raise: false
  # advance/back are driven from the projection machine (a clicker sends key events to this page),
  # so they are token-gated like the view rather than editor-authenticated, and accept a
  # cross-origin-free fetch without the session CSRF token.
  skip_before_action :verify_authenticity_token, only: %i[advance back], raise: false
  layout "follower"

  def show
    @session = find_session!
  end

  private

  def find_session!
    LiveSession.active.find_by!(projector_token: params[:token])
  rescue ActiveRecord::RecordNotFound
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    nil
  end
end

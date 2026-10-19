class ProjectorController < ApplicationController
  # Public follower view — no sign-in. Access is gated solely by possession of a valid token.
  skip_before_action :set_current_user, raise: false
  layout "follower"

  def show
    @session = LiveSession.active.find_by!(projector_token: params[:token])
  rescue ActiveRecord::RecordNotFound
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end

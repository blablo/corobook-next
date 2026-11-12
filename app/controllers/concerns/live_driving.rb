# Next/Back for a token-gated screen: the projector (a clicker plugged into the projection
# machine) or the speaker view (the pastor's tablet). Holding the token is the capability to
# drive, so these are fetches from the page without the session CSRF token, and a bad or revoked
# token is a 404. The follower streams then update every screen.
#
#   class SpeakerController < ApplicationController
#     include LiveDriving
#     driven_by :speaker_token
module LiveDriving
  extend ActiveSupport::Concern

  included do
    class_attribute :driving_token, instance_writer: false
    skip_before_action :verify_authenticity_token, only: %i[advance back], raise: false
  end

  class_methods do
    # The live_sessions column that holds this screen's token.
    def driven_by(column) = (self.driving_token = column)
  end

  def advance = drive(:next)
  def back = drive(:back)

  private

  def drive(direction)
    session = find_session!
    return if session.nil?

    position = Corobook::LivePosition.new(session.service_set)
    target = direction == :next ? position.next_stop(*session.current_stop) : position.prev_stop(*session.current_stop)
    session.move_to!(target) if target
    head :no_content
  end

  def find_session!
    LiveSession.active.find_by!(driving_token => params[:token])
  rescue ActiveRecord::RecordNotFound
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    nil
  end
end

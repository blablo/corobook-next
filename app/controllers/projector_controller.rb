class ProjectorController < ApplicationController
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

  def advance
    move { |pos| pos.next_stop(@session.current_set_item_id, @session.current_section_index) }
  end

  def back
    move { |pos| pos.prev_stop(@session.current_set_item_id, @session.current_section_index) }
  end

  private

  def find_session!
    LiveSession.active.find_by!(projector_token: params[:token])
  rescue ActiveRecord::RecordNotFound
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    nil
  end

  # Same position move as the operator (shared LivePosition), gated by the projector token.
  # Possession of the token is the capability to drive the display.
  def move
    @session = find_session!
    return if @session.nil?

    pos = Corobook::LivePosition.new(@session.service_set)
    target = yield(pos)
    if target
      begin
        @session.with_lock do
          @session.update!(
            current_set_item_id: target.set_item_id,
            current_section_index: target.section_index,
            position_version: @session.position_version + 1
          )
          capture_usage(@session)
        end
        Corobook::LiveBroadcast.position(@session)
      rescue ActiveRecord::StaleObjectError
        # A concurrent driver moved it; the follower stream already carries the latest.
      end
    end
    head :no_content
  end

  def capture_usage(session)
    item = session.current_set_item
    return unless item&.item_type == "song"

    UsageEvent.capture(live_session: session, song: item.song)
  end
end

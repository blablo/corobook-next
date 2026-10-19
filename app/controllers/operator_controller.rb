class OperatorController < ApplicationController
  before_action :require_sign_in
  before_action :require_editor
  before_action :set_session

  def show; end

  def advance
    move { |pos| pos.next_stop(@session.current_set_item_id, @session.current_section_index) }
  end

  def back
    move { |pos| pos.prev_stop(@session.current_set_item_id, @session.current_section_index) }
  end

  # Jump to the first section of any item already in the Set (Req 6.10).
  def goto
    move { |pos| pos.first_stop_of(params[:set_item_id].to_i) }
  end

  private

  def set_session
    @session = find_in_church(:live_sessions, params[:id])
  end

  # Resolve the target stop, then update position + bump position_version in one transaction
  # (optimistic lock_version guards a concurrent operator), capture usage, and broadcast inline.
  def move
    pos = Corobook::LivePosition.new(@session.service_set)
    target = yield(pos)
    return redirect_to(operator_path(@session)) if target.nil?

    begin
      @session.with_lock do
        @session.update!(
          current_set_item_id: target.set_item_id,
          current_section_index: target.section_index,
          position_version: @session.position_version + 1
        )
        capture_usage(@session) # 8.1 hooks here — additive, inside the position transaction
      end
    rescue ActiveRecord::StaleObjectError
      flash.now[:alert] = "Another operator changed the session; reloaded."
    end

    broadcast_position(@session)
    respond_to do |format|
      format.html { redirect_to operator_path(@session) }
      format.turbo_stream { head :ok }
    end
  end

  # Seam for CCLI usage capture (Phase 8). No-op until 8.1 implements it.
  def capture_usage(_session); end

  # Inline broadcast to both follower streams (never via Solid Queue; church is held explicitly).
  def broadcast_position(session)
    Corobook::LiveBroadcast.position(session)
  end
end

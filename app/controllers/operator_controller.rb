class OperatorController < ApplicationController
  layout "shell"
  before_action :require_sign_in
  before_action :require_editor
  before_action :set_session

  # Presenter view: the live slide (Now) beside the real rendered NEXT slide, like Keynote.
  def show
    position = Corobook::LivePosition.new(@session.service_set)
    current = [ @session.current_set_item_id, @session.current_section_index, @session.current_chunk_index ]
    @stop_index = position.index_of(*current)
    @stop_count = position.stops.length
    next_stop = position.next_stop(*current)
    @next_session = preview_session_for(next_stop) if next_stop
  end

  def advance
    move { |pos| pos.next_stop(@session.current_set_item_id, @session.current_section_index, @session.current_chunk_index) }
  end

  def back
    move { |pos| pos.prev_stop(@session.current_set_item_id, @session.current_section_index, @session.current_chunk_index) }
  end

  # Jump to the first section of any item already in the Set (Req 6.10).
  def goto
    move { |pos| pos.first_stop_of(params[:set_item_id].to_i) }
  end

  def blank
    update_projector_state { @session.blanked = !@session.blanked }
  end

  def font
    delta = params[:dir] == "down" ? -10 : 10
    update_projector_state { @session.font_scale = @session.font_scale.clamp(50, 400) + delta }
  end

  def end_session
    @session.end!
    Corobook::LiveBroadcast.ended(@session)
    redirect_to service_set_path(@session.service_set), notice: "Service ended."
  end

  private

  def set_session
    @session = find_in_church(:live_sessions, params[:id])
  end

  # An unsaved, read-only copy of the live session moved to `stop`, so the Next preview renders
  # through the exact same projector frame as the live one. Never blanked: Next always shows the
  # slide that will come up.
  def preview_session_for(stop)
    @session.dup.tap do |s|
      s.assign_attributes(current_set_item_id: stop.set_item_id, current_section_index: stop.section_index,
                          current_chunk_index: stop.chunk_index, blanked: false)
      s.readonly!
    end
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
          current_chunk_index: target.chunk_index,
          position_version: @session.position_version + 1
        )
        capture_usage(@session) # 8.1 hooks here — additive, inside the position transaction
      end
    rescue ActiveRecord::StaleObjectError
      flash.now[:alert] = "Another operator changed the session; reloaded."
    end

    broadcast_position(@session)
    redirect_to operator_path(@session)
  end

  # CCLI usage capture (§7): when a song becomes current, record one idempotent usage event.
  # Runs inside the position transaction; live_session is passed explicitly (never Current).
  def capture_usage(session)
    item = session.current_set_item
    return unless item&.item_type == "song"

    UsageEvent.capture(live_session: session, song: item.song)
  end

  # Apply a projector-state change (blank/font), clamp font, bump version, broadcast inline.
  def update_projector_state
    @session.with_lock do
      yield
      @session.font_scale = @session.font_scale.clamp(50, 400)
      @session.position_version += 1
      @session.save!
    end
    Corobook::LiveBroadcast.position(@session)
    redirect_to operator_path(@session)
  end

  # Inline broadcast to both follower streams (never via Solid Queue; church is held explicitly).
  def broadcast_position(session)
    Corobook::LiveBroadcast.position(session)
  end
end

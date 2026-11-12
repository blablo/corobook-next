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

  # Take the speaker's whiteboard (or slide drawing) off the projector, e.g. when the pastor
  # walks away with it still up.
  def stop_whiteboard
    Corobook::Whiteboard.new(@session).stop!
    redirect_to operator_path(@session)
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

  # Resolve the target stop and move there (LiveSession#move_to! bumps the version, records usage
  # and broadcasts). A concurrent move by another driver wins; this page just reloads.
  def move
    pos = Corobook::LivePosition.new(@session.service_set)
    target = yield(pos)
    @session.move_to!(target) if target
    redirect_to operator_path(@session)
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
end

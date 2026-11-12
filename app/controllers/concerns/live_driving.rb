# Next/Back actions for a token-gated screen: the projector (a clicker plugged into the
# projection machine) or the speaker view (the pastor's tablet). Holding the token is the
# capability to drive; the follower streams then update every screen. The including controller
# defines find_session!, which renders 404 and returns nil for a bad or revoked token.
module LiveDriving
  extend ActiveSupport::Concern

  def advance = drive(:next)
  def back = drive(:back)

  private

  def drive(direction)
    session = find_session!
    return if session.nil?

    position = Corobook::LivePosition.new(session.service_set)
    current = [ session.current_set_item_id, session.current_section_index, session.current_chunk_index ]
    target = direction == :next ? position.next_stop(*current) : position.prev_stop(*current)
    session.move_to!(target) if target
    head :no_content
  end
end

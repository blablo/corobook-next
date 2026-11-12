# Transport for the speaker's whiteboard (Corobook::Whiteboard holds the logic and the state).
#
# Two kinds of subscriber:
# - the speaker view, with `speaker: <speaker_token>`: may draw, undo, clear, start and stop.
# - a screen that only shows it (projector, operator), with `viewer: <signed session id>` from
#   LiveSession#whiteboard_viewer_key.
# Every action looks the session up by the speaker token again, so the link stops working the
# moment the service ends.
class WhiteboardChannel < ActionCable::Channel::Base
  def subscribed
    session = speaker_session || viewer_session
    return reject if session.nil?

    stream_for session
    transmit Corobook::Whiteboard.new(session).state
  end

  def draw(data)
    as_speaker { |board| board.relay_live!(data["stroke"], src: data["src"], id: data["id"]) }
  end

  def stroke(data)
    as_speaker { |board| board.add_stroke!(data["stroke"], src: data["src"], id: data["id"]) }
  end

  def start(data) = as_speaker { |board| board.start!(data["mode"]) }
  def stop(_data = nil) = as_speaker(&:stop!)
  def undo(_data = nil) = as_speaker(&:undo!)
  def clear(_data = nil) = as_speaker(&:clear!)
  def dark(data) = as_speaker { |board| board.dark!(data["dark"]) }

  private

  def speaker_session
    token = params[:speaker].presence
    token && LiveSession.active.find_by(speaker_token: token.to_s)
  end

  def viewer_session
    id = LiveSession.whiteboard_viewer_id(params[:viewer])
    id && LiveSession.active.find_by(id:)
  end

  def as_speaker
    session = speaker_session
    yield Corobook::Whiteboard.new(session) if session
  end
end

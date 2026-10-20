class LiveSessionsController < ApplicationController
  before_action :require_sign_in
  before_action :require_editor

  # Launch a run of a Set: create the authoritative LiveSession and open the operator.
  # A church may only have one active service at a time, so handle the collision gracefully
  # rather than letting AlreadyLiveError 500: resume this set's own run, or explain the conflict.
  def create
    service_set = find_in_church(:service_sets, params[:id])
    session = LiveSession.launch(service_set)
    redirect_to operator_path(session)
  rescue LiveSession::AlreadyLiveError
    mine = service_set.live_sessions.find_by(status: "active")
    return redirect_to(operator_path(mine)) if mine

    live = church_scope(:live_sessions).find_by(status: "active")
    redirect_to service_set_path(service_set),
      alert: "#{live&.service_set&.name || 'Another set'} is already live. End that service before starting this one."
  end
end

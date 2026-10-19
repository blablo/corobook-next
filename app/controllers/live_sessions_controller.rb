class LiveSessionsController < ApplicationController
  before_action :require_sign_in
  before_action :require_editor

  # Launch a run of a Set: create the authoritative LiveSession and open the operator.
  def create
    service_set = find_in_church(:service_sets, params[:id])
    session = LiveSession.launch(service_set)
    redirect_to operator_path(session)
  end
end

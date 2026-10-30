class MusicianController < ApplicationController
  # Public follower view — no sign-in. Gated solely by the musician token.
  skip_before_action :set_current_user, raise: false
  layout "follower"

  # Per-run link (/m/:token): only valid while that live session is active.
  def show
    @session = LiveSession.active.find_by!(musician_token: params[:token])
    load_chart(@session.service_set)
    @key_scope = @session.musician_token
  rescue ActiveRecord::RecordNotFound
    not_found
  end

  # Permanent per-service link (/m/s/:token), e.g. from the band email. While the service is live
  # it follows the operator exactly like the per-run link; otherwise it shows the same chart
  # without a live position, so musicians can rehearse from it during the week.
  def service
    service_set = ServiceSet.find_by!(musician_token: params[:token])
    @session = service_set.active_live_session
    load_chart(service_set)
    # Key/capo choice is remembered per service, so it survives going live.
    @key_scope = service_set.musician_token
    render :show
  rescue ActiveRecord::RecordNotFound
    not_found
  end

  private

  def load_chart(service_set)
    @service_set = service_set
    # The follower's chosen key/capo come from the request (persisted client-side in localStorage);
    # each musician renders independently server-side (§6.3).
    @target_key = params[:key]
    @semitones = params[:semitones].to_i
    @capo = params[:capo].presence

    # The WHOLE set in order, transposed to this musician's key — the scrollable chart. Includes
    # chords-only intros/instrumentals (a player needs them) even though the projector skips them.
    @set_rows = Corobook::MusicianSetView.new(
      service_set, target_key: @target_key, semitones: @semitones, capo: @capo
    ).rows
  end

  def not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end

class MusicianController < ApplicationController
  # Public follower view — no sign-in. Gated solely by the musician token.
  skip_before_action :set_current_user, raise: false
  layout "follower"

  def show
    @session = LiveSession.active.find_by!(musician_token: params[:token])
    # The follower's chosen key/capo come from the request (persisted client-side in localStorage);
    # each musician renders independently server-side (§6.3).
    @target_key = params[:key]
    @semitones = params[:semitones].to_i
    @capo = params[:capo].presence

    # The WHOLE set in order, transposed to this musician's key — the scrollable chart. Includes
    # chords-only intros/instrumentals (a player needs them) even though the projector skips them.
    @set_rows = Corobook::MusicianSetView.new(
      @session.service_set, target_key: @target_key, semitones: @semitones, capo: @capo
    ).rows
  rescue ActiveRecord::RecordNotFound
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end

class SettingsController < ApplicationController
  layout "shell"
  before_action :require_sign_in
  before_action :require_admin

  # General settings (church subdomain).
  def show
    @church = Current.church
  end

  # Projection settings (per-church projector look & behaviour).
  def projection
    @church = Current.church
  end

  def update
    @church = Current.church
    # Which sub-page the form was submitted from — drives both the error re-render and the
    # success redirect, so each sub-page round-trips to itself.
    section = params[:section].to_s == "projection" ? :projection : :show

    if @church.update(settings_params)
      redirect_to(section == :projection ? projection_settings_path : settings_path,
                  notice: "Settings saved.")
    else
      render section, status: :unprocessable_entity
    end
  end

  private

  def settings_params
    params.require(:church).permit(
      :subdomain,
      :projector_bg_color, :projector_text_color,
      :projector_bg_type, :projector_bg_color2, :projector_bg_gradient_angle,
      :projector_lyric_case, :projector_title_case,
      :projector_font, :projector_line_height,
      :projector_bold, :projector_show_credits,
      :projector_valign, :projector_pagination, :projector_lines_per_slide, :projector_font_size,
      :projector_min_font_size
    )
  end
end

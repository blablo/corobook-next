class SettingsController < ApplicationController
  layout "shell"
  before_action :require_sign_in
  before_action :require_admin

  def show
    @church = Current.church
  end

  def update
    @church = Current.church
    if @church.update(settings_params)
      redirect_to settings_path, notice: "Settings saved."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def settings_params
    params.require(:church).permit(
      :subdomain,
      :projector_bg_color, :projector_text_color,
      :projector_lyric_case, :projector_title_case,
      :projector_font, :projector_line_height,
      :projector_bold, :projector_show_credits,
      :projector_valign, :projector_pagination, :projector_lines_per_slide
    )
  end
end

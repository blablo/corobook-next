class InvitationAcceptancesController < ApplicationController
  layout "shell"

  # Public: no require_sign_in / require_admin. Tenancy comes from the token, not Current.
  # set_current_user (from Authentication) still runs — harmless when nobody is signed in — so
  # session[:user_id] is available for sign_in on a successful accept.

  def show
    @invitation = Invitation.find_acceptable_by_token(params[:token])
    render_invalid unless @invitation
  end

  def create
    @invitation = Invitation.find_acceptable_by_token(params[:token])
    return render_invalid unless @invitation

    church = @invitation.church

    if church.users.exists?(email: @invitation.email)
      # 4.5: the email became a member between invite and accept — do not 500 on the unique index.
      redirect_to login_path,
                  alert: "You already have an account for #{church.name}. Please sign in."
      return
    end

    user = church.users.new(
      email: @invitation.email,
      role: @invitation.role,
      password: params[:password],
      password_confirmation: params[:password_confirmation]
    )

    ActiveRecord::Base.transaction do
      user.save!
      @invitation.update!(accepted_at: Time.current) # consumes the pending-index slot
    end

    sign_in(user) # resets the session, so an already-signed-in visitor is handled (4.6)
    redirect_to root_path, notice: "Welcome to #{church.name}!"
  rescue ActiveRecord::RecordInvalid
    @user = user
    flash.now[:alert] = user.errors.full_messages.to_sentence.presence || "Could not set your password."
    render :show, status: :unprocessable_entity
  end

  private

  def render_invalid
    render :invalid, status: :gone
  end
end

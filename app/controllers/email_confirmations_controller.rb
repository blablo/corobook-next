class EmailConfirmationsController < ApplicationController
  layout "public"

  # Confirm an account from the emailed link, then sign the user in.
  def show
    user = User.find_by_confirmation_token(params[:token])
    if user
      user.confirm!
      sign_in(user)
      redirect_to root_path, notice: "Your account is confirmed — welcome to Corobook!"
    else
      redirect_to login_path, alert: "That confirmation link is invalid or has expired. Try signing in to resend it."
    end
  end

  # Resend a fresh confirmation link to an unconfirmed account. Always answers the same way so it
  # never reveals whether an email exists.
  def resend
    email = params[:email].to_s.strip.downcase
    user = User.where(confirmed_at: nil).find_by(email: email)
    if user
      user.regenerate_confirmation_token!
      user.save!
      deliver(user)
    end
    redirect_to signup_check_email_path(email: email), notice: "If that account needs confirming, we've sent a fresh link."
  end

  private

  def deliver(user)
    RegistrationsMailer.confirm(user, user.raw_confirmation_token).deliver_later
  rescue StandardError
    nil
  ensure
    if user.raw_confirmation_token.present? && (Rails.env.local? || Rails.application.config.action_mailer.perform_deliveries == false)
      flash[:confirm_url] = email_confirmation_url(user.raw_confirmation_token)
    end
  end
end

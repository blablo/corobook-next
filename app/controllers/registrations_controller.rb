class RegistrationsController < ApplicationController
  layout "public"
  before_action :redirect_if_signed_in

  def new
    @church = Church.new
    @user = User.new
  end

  def create
    @church = Church.new(church_params)
    @user = @church.users.build(user_params.merge(role: "admin"))
    @user.regenerate_confirmation_token! # unconfirmed until the emailed link is clicked

    ActiveRecord::Base.transaction do
      @church.save!
      @user.save!
    end
    deliver_confirmation(@user)
    # Do NOT sign in — the account is gated until the email is confirmed.
    redirect_to signup_check_email_path(email: @user.email), notice: "Almost there — check your email to confirm your account."
  rescue ActiveRecord::RecordInvalid
    # Surface errors from whichever record failed; the transaction rolled back, so nothing persisted.
    flash.now[:alert] = (@church.errors.full_messages + @user.errors.full_messages).to_sentence.presence ||
                        "Could not create your account."
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique => e
    # The DB unique index fired where the model validation's check-then-save window raced (two
    # signups grabbing the same subdomain at once). Turn the 500 into the same friendly error.
    if e.message.include?("subdomain")
      @church.errors.add(:subdomain, "has already been taken")
    else
      @church.errors.add(:base, "Could not create your account. Please try again.")
    end
    flash.now[:alert] = @church.errors.full_messages.to_sentence
    render :new, status: :unprocessable_entity
  end

  # "Check your email" confirmation-pending page shown after signup.
  def check_email
    @email = params[:email]
  end

  private

  # Best-effort delivery: the account is authoritative, mail is a side effect. In dev (and when
  # mail isn't configured) we also surface the confirmation link on-screen as a fallback.
  def deliver_confirmation(user)
    RegistrationsMailer.confirm(user, user.raw_confirmation_token).deliver_later
  rescue StandardError
    nil
  ensure
    if user.raw_confirmation_token.present? && (Rails.env.local? || Rails.application.config.action_mailer.perform_deliveries == false)
      flash[:confirm_url] = email_confirmation_url(user.raw_confirmation_token)
    end
  end

  def church_params
    params.require(:church).permit(:name, :subdomain)
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end

  def redirect_if_signed_in
    redirect_to root_path if signed_in?
  end
end

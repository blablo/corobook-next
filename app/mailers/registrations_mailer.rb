class RegistrationsMailer < ApplicationMailer
  # raw_token is passed explicitly — Current is unset on the mailer path and the token is never
  # stored in plaintext, so the controller that minted it hands it over here.
  def confirm(user, raw_token)
    @user   = user
    @church = user.church
    @url    = email_confirmation_url(raw_token)

    mail to: user.email, subject: "Confirm your Corobook account for #{@church.name}"
  end
end

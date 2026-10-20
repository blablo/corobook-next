class InvitationsMailer < ApplicationMailer
  # raw_token is passed explicitly — Current is unset on the mailer path, and the token is never
  # stored in plaintext, so the controller that minted it hands it over here.
  def invite(invitation, raw_token)
    @invitation = invitation
    @church     = invitation.church
    @inviter    = invitation.invited_by
    @role       = invitation.role
    @url        = accept_invitation_url(token: raw_token)

    mail to: invitation.email,
         subject: "You're invited to #{@church.name} on Corobook"
  end
end

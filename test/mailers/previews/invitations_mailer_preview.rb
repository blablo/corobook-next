# Preview the branded invitation email at
#   /rails/mailers/invitations_mailer/invite
# Uses unsaved in-memory objects so it never touches the database.
class InvitationsMailerPreview < ActionMailer::Preview
  def invite
    church  = Church.new(name: "Palabra Fiel")
    inviter = User.new(email: "pastor@palabrafiel.org", church: church, role: "admin")
    invitation = Invitation.new(
      church: church, invited_by: inviter,
      email: "nuevo.musico@example.com", role: "editor"
    )
    InvitationsMailer.invite(invitation, "preview-token-abc123")
  end
end

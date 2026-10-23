# Preview the branded confirmation email at
#   /rails/mailers/registrations_mailer/confirm
# Uses unsaved in-memory objects so it never touches the database.
class RegistrationsMailerPreview < ActionMailer::Preview
  def confirm
    church = Church.new(name: "Palabra Fiel")
    user   = User.new(email: "nuevo@palabrafiel.org", church: church, role: "admin")
    RegistrationsMailer.confirm(user, "preview-token-xyz789")
  end
end

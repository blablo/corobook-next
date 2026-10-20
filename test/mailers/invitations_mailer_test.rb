require "test_helper"

class InvitationsMailerTest < ActionMailer::TestCase
  setup do
    @church = Church.create!(name: "Central")
    @admin  = User.create!(church: @church, email: "admin@example.com", password: "secret123", role: "admin")
    @inv    = @church.invitations.new(email: "invitee@example.com", invited_by: @admin, role: "editor")
    @raw    = @inv.regenerate_token!
    @inv.save!
  end

  test "invite email addresses the invitee and names the church, inviter, role, and accept URL" do
    mail = InvitationsMailer.invite(@inv, @raw)

    assert_equal [ "invitee@example.com" ], mail.to
    assert_includes mail.subject, @church.name

    body = mail.body.encoded
    assert_includes body, @admin.email
    assert_includes body, "editor"
    assert_match %r{https?://[^/\s]+/invitations/#{Regexp.escape(@raw)}/accept}, body
  end

  test "the accept URL is absolute with the configured host, not from Current" do
    mail = InvitationsMailer.invite(@inv, @raw)
    assert_match %r{https?://[^/]+/invitations/#{Regexp.escape(@raw)}/accept}, mail.body.encoded
  end
end

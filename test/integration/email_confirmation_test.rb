require "test_helper"

class EmailConfirmationTest < ActionDispatch::IntegrationTest
  # Create a church + unconfirmed admin the way signup does, returning [user, raw_token].
  def signup!(email: "pastor@example.com", name: "Nueva", subdomain: nil)
    church = Church.new(name: name, subdomain: subdomain)
    user = church.users.build(email: email, password: "secret123", role: "admin")
    token = user.regenerate_confirmation_token!
    church.save!; user.save!
    [ user, token ]
  end

  test "an unconfirmed user cannot sign in and is offered a resend" do
    user, _ = signup!
    post login_path, params: { church_id: user.church_id, email: user.email, password: "secret123" }
    assert_response :unprocessable_entity
    assert_select "[data-role=unconfirmed-notice]"
    assert_select "[data-role=resend-confirmation]"
  end

  test "a valid confirmation link confirms the account and signs in" do
    user, token = signup!
    get email_confirmation_path(token)
    assert_redirected_to root_path
    assert user.reload.confirmed?
    assert_nil user.confirmation_token_digest, "the token is spent after confirmation"
    # Now signed in — root shows the dashboard.
    follow_redirect!
    assert_select "[data-role=home]"
  end

  test "a confirmed user can then sign in normally" do
    user, token = signup!
    get email_confirmation_path(token) # confirms + signs in
    delete logout_path
    post login_path, params: { church_id: user.church_id, email: user.email, password: "secret123" }
    assert_redirected_to root_path
  end

  test "an invalid/expired token is rejected" do
    get email_confirmation_path("not-a-real-token")
    assert_redirected_to login_path
  end

  test "an expired token does not confirm" do
    user, token = signup!
    user.update!(confirmation_sent_at: 3.days.ago) # past the 2-day expiry
    get email_confirmation_path(token)
    assert_redirected_to login_path
    assert_not user.reload.confirmed?
  end

  test "resend issues a fresh link and always redirects the same way" do
    user, _ = signup!
    old_digest = user.confirmation_token_digest
    post resend_confirmation_path, params: { email: user.email }
    assert_redirected_to signup_check_email_path(email: user.email)
    assert_not_equal old_digest, user.reload.confirmation_token_digest
  end

  test "resend for an unknown email still redirects without revealing anything" do
    post resend_confirmation_path, params: { email: "nobody@example.com" }
    assert_redirected_to signup_check_email_path(email: "nobody@example.com")
  end

  test "invited members are confirmed on accept and never hit the gate" do
    church = Church.create!(name: "Gracia")
    admin = church.users.create!(email: "admin@example.com", password: "secret123", role: "admin", confirmed_at: Time.current)
    invitation = church.invitations.build(email: "new@example.com", role: "editor", invited_by: admin)
    invitation.regenerate_token!
    invitation.save!

    post accept_invitation_path(invitation.raw_token),
         params: { password: "secret123", password_confirmation: "secret123" }
    assert_redirected_to root_path
    user = church.users.find_by(email: "new@example.com")
    assert user.confirmed?, "an invited member is confirmed by accepting the invite"
  end
end

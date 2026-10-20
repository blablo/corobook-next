require "test_helper"

class InvitationAcceptancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    @admin  = User.create!(church: @church, email: "admin@example.com", password: "secret123", role: "admin")
  end

  def pending_invite(email: "new@example.com", role: "editor")
    inv = Invitation.new(church: @church, invited_by: @admin, email: email, role: role)
    raw = inv.regenerate_token!
    inv.save!
    [ inv, raw ]
  end

  # --- show ---

  test "valid token renders the accept form with church and email" do
    _inv, raw = pending_invite
    get accept_invitation_path(token: raw)
    assert_response :success
    assert_includes response.body, @church.name
    assert_includes response.body, "new@example.com"
  end

  test "unknown token renders the neutral invalid page and reveals no church" do
    get accept_invitation_path(token: "nope")
    assert_response :gone
    assert_includes response.body, "no longer valid"
    assert_not_includes response.body, @church.name
  end

  test "expired token renders invalid" do
    inv, raw = pending_invite
    inv.update!(expires_at: 1.minute.ago)
    get accept_invitation_path(token: raw)
    assert_response :gone
  end

  test "already-accepted token renders invalid" do
    inv, raw = pending_invite
    inv.update!(accepted_at: Time.current)
    get accept_invitation_path(token: raw)
    assert_response :gone
  end

  # --- create ---

  test "valid accept creates a church-scoped user with the invited role, consumes token, signs in" do
    inv, raw = pending_invite(email: "joiner@example.com", role: "editor")
    assert_difference -> { @church.users.count }, 1 do
      post accept_invitation_path(token: raw),
           params: { password: "newpass123", password_confirmation: "newpass123" }
    end
    assert_redirected_to root_path
    user = @church.users.find_by(email: "joiner@example.com")
    assert user
    assert_equal "editor", user.role
    assert inv.reload.accepted_at.present?, "invitation should be consumed"

    # token no longer accepts
    get accept_invitation_path(token: raw)
    assert_response :gone
  end

  test "password mismatch re-renders and creates nothing" do
    _inv, raw = pending_invite
    assert_no_difference -> { User.count } do
      post accept_invitation_path(token: raw),
           params: { password: "newpass123", password_confirmation: "different" }
    end
    assert_response :unprocessable_entity
  end

  test "short password re-renders and creates nothing" do
    _inv, raw = pending_invite
    assert_no_difference -> { User.count } do
      post accept_invitation_path(token: raw),
           params: { password: "x", password_confirmation: "x" }
    end
    assert_response :unprocessable_entity
  end

  test "already-a-member on accept is graceful, not a 500" do
    inv, raw = pending_invite(email: "dup@example.com")
    User.create!(church: @church, email: "dup@example.com", password: "secret123", role: "editor")
    post accept_invitation_path(token: raw),
         params: { password: "newpass123", password_confirmation: "newpass123" }
    assert_redirected_to login_path
    assert_nil inv.reload.accepted_at, "invite not consumed when member already exists"
  end

  test "accept while signed in as another church user still creates and signs in the new user" do
    other = Church.create!(name: "Norte")
    User.create!(church: other, email: "someone@example.com", password: "secret123", role: "admin")
    post login_path, params: { church_id: other.id, email: "someone@example.com", password: "secret123" }

    _inv, raw = pending_invite(email: "fresh@example.com", role: "admin")
    post accept_invitation_path(token: raw),
         params: { password: "newpass123", password_confirmation: "newpass123" }
    assert_redirected_to root_path
    assert @church.users.find_by(email: "fresh@example.com")
  end
end

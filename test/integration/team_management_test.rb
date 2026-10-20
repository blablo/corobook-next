require "test_helper"

class TeamManagementTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    @other  = Church.create!(name: "Norte")
    @admin  = User.create!(church: @church, email: "admin@example.com", password: "secret123", role: "admin")
    @editor = User.create!(church: @church, email: "editor@example.com", password: "secret123", role: "editor")
  end

  def login(user)
    post login_path, params: { church_id: user.church_id, email: user.email, password: "secret123" }
  end

  # --- Team#show access (3.1) ---

  test "admin sees own church members and pending invites only" do
    inv = @church.invitations.new(email: "pending@example.com", invited_by: @admin, role: "editor")
    inv.regenerate_token!; inv.save!
    other_inv = @other.invitations.new(email: "elsewhere@example.com",
                                       invited_by: User.create!(church: @other, email: "a@other.com", password: "secret123", role: "admin"),
                                       role: "editor")
    other_inv.regenerate_token!; other_inv.save!

    login(@admin)
    get team_path
    assert_response :success
    assert_includes response.body, "pending@example.com"
    assert_not_includes response.body, "elsewhere@example.com"
    assert_includes response.body, "editor@example.com"
  end

  test "editor is denied the team page" do
    login(@editor)
    get team_path
    assert_redirected_to login_path
  end

  test "anonymous is redirected to login" do
    get team_path
    assert_redirected_to login_path
  end

  # --- Invitations#create (3.2) ---

  test "admin creates a pending invitation" do
    login(@admin)
    assert_difference -> { @church.invitations.pending.count }, 1 do
      post invitations_path, params: { invitation: { email: "new@example.com", role: "editor" } }
    end
    assert_redirected_to team_path
  end

  test "inviting an existing member is rejected" do
    login(@admin)
    assert_no_difference -> { Invitation.count } do
      post invitations_path, params: { invitation: { email: @editor.email, role: "editor" } }
    end
    assert_redirected_to team_path
    assert_equal "That person is already a member.", flash[:alert]
  end

  test "inviting an email with a pending invite refreshes it, not duplicates" do
    login(@admin)
    post invitations_path, params: { invitation: { email: "dup@example.com", role: "editor" } }
    inv = @church.invitations.pending.find_by(email: "dup@example.com")
    old_expiry = inv.expires_at
    old_digest = inv.token_digest

    assert_no_difference -> { @church.invitations.pending.count } do
      post invitations_path, params: { invitation: { email: "dup@example.com", role: "admin" } }
    end
    inv.reload
    assert_not_equal old_digest, inv.token_digest, "token refreshed"
    assert inv.expires_at >= old_expiry
    assert_equal "admin", inv.role
  end

  test "invalid email is rejected" do
    login(@admin)
    assert_no_difference -> { Invitation.count } do
      post invitations_path, params: { invitation: { email: "not-an-email", role: "editor" } }
    end
    assert_redirected_to team_path
  end

  test "editor cannot create an invitation" do
    login(@editor)
    assert_no_difference -> { Invitation.count } do
      post invitations_path, params: { invitation: { email: "x@example.com", role: "editor" } }
    end
    assert_redirected_to login_path
  end

  # --- Invitations#resend / #destroy (3.2) ---

  test "resend regenerates the token and expiry" do
    inv = @church.invitations.new(email: "r@example.com", invited_by: @admin, role: "editor")
    inv.regenerate_token!; inv.save!
    old = inv.token_digest
    login(@admin)
    post resend_invitation_path(inv)
    assert_not_equal old, inv.reload.token_digest
  end

  test "revoke deletes the invitation so its token stops accepting" do
    inv = @church.invitations.new(email: "rv@example.com", invited_by: @admin, role: "editor")
    raw = inv.regenerate_token!; inv.save!
    login(@admin)
    assert_difference -> { Invitation.count }, -1 do
      delete invitation_path(inv)
    end
    assert_nil Invitation.find_acceptable_by_token(raw)
  end

  test "cross-church invitation id is a 404" do
    other_admin = User.create!(church: @other, email: "oa@other.com", password: "secret123", role: "admin")
    inv = @other.invitations.new(email: "z@other.com", invited_by: other_admin, role: "editor")
    inv.regenerate_token!; inv.save!
    login(@admin)
    delete invitation_path(inv)
    assert_response :not_found
  end

  # --- Members#update / #destroy + last-admin guard (3.3) ---

  test "admin changes a member role" do
    login(@admin)
    patch member_path(@editor), params: { user: { role: "admin" } }
    assert_equal "admin", @editor.reload.role
  end

  test "demoting the sole admin is blocked" do
    login(@admin)
    patch member_path(@admin), params: { user: { role: "editor" } }
    assert_equal "admin", @admin.reload.role
    assert_equal "A church must have at least one admin.", flash[:alert]
  end

  test "removing the sole admin is blocked" do
    login(@admin)
    assert_no_difference -> { User.count } do
      delete member_path(@admin)
    end
    assert_equal "A church must have at least one admin.", flash[:alert]
  end

  test "a non-last admin can be demoted and removed" do
    admin2 = User.create!(church: @church, email: "admin2@example.com", password: "secret123", role: "admin")
    login(@admin)
    patch member_path(admin2), params: { user: { role: "editor" } }
    assert_equal "editor", admin2.reload.role

    admin3 = User.create!(church: @church, email: "admin3@example.com", password: "secret123", role: "admin")
    assert_difference -> { User.count }, -1 do
      delete member_path(admin3)
    end
  end

  test "editor cannot manage members" do
    login(@editor)
    patch member_path(@admin), params: { user: { role: "editor" } }
    assert_redirected_to login_path
    assert_equal "admin", @admin.reload.role
  end

  test "cross-church member id is a 404" do
    other_user = User.create!(church: @other, email: "ou@other.com", password: "secret123", role: "editor")
    login(@admin)
    delete member_path(other_user)
    assert_response :not_found
  end
end

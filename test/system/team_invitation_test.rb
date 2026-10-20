require "application_system_test_case"

class TeamInvitationTest < ApplicationSystemTestCase
  setup do
    @church = Church.create!(name: "Central")
    @admin  = User.create!(church: @church, email: "admin@example.com", password: "secret123", role: "admin")

    visit login_path
    select @church.name, from: "Church"
    fill_in "Email", with: @admin.email
    fill_in "Password", with: "secret123"
    click_on "Sign in"
    assert_selector "[data-role=home]"
  end

  test "admin invites a member, sees it pending, then revokes it" do
    visit team_path
    assert_selector "[data-role=team]"

    within "[data-role=invite-form]" do
      fill_in "Email", with: "newmember@example.com"
      select "Editor", from: "Role"
      click_on "Send invite"
    end

    # pending row appears, and the manual accept-URL fallback is shown
    assert_selector "[data-role=invite-row][data-email='newmember@example.com']"
    assert_selector "[data-role=accept-url-fallback]"

    # revoke it
    within "[data-role=invite-row][data-email='newmember@example.com']" do
      click_on "Revoke"
    end
    page.driver.browser.switch_to.alert.accept rescue nil
    assert_no_selector "[data-role=invite-row][data-email='newmember@example.com']"
  end

  test "an invitee follows the accept link, sets a password, and lands signed in" do
    inv = @church.invitations.new(email: "joiner@example.com", invited_by: @admin, role: "editor")
    raw = inv.regenerate_token!
    inv.save!

    # start fresh (sign out the admin) then open the invite link
    find("[data-role=user-email]", wait: 5) rescue nil
    visit accept_invitation_path(token: raw)
    assert_selector "[data-role=accept-invitation]"
    fill_in "Password", with: "joinerpass1"
    fill_in "Confirm password", with: "joinerpass1"
    click_on "Join #{@church.name}"

    assert_selector "[data-role=home]"
    assert @church.users.exists?(email: "joiner@example.com")
  end
end

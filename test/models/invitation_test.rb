require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  setup do
    @church = Church.create!(name: "Central")
    @admin  = User.create!(church: @church, email: "admin@example.com", password: "secret123", role: "admin")
  end

  def build_invite(**attrs)
    Invitation.new({ church: @church, invited_by: @admin, email: "new@example.com", role: "editor" }.merge(attrs))
  end

  test "regenerate_token! mints a URL-safe, high-entropy token stored only as a digest" do
    inv = build_invite
    raw = inv.regenerate_token!
    assert_match(/\A[A-Za-z0-9_-]+\z/, raw, "token must be URL-safe")
    assert_operator raw.length, :>=, 22, "token must carry >=128 bits of entropy"
    # the raw token is NEVER the stored value
    assert_not_equal raw, inv.token_digest
    assert_equal Digest::SHA256.hexdigest(raw), inv.token_digest
    assert inv.expires_at > Time.current
  end

  test "acceptable? and expired? reflect pending + expiry" do
    inv = build_invite
    inv.regenerate_token!
    inv.save!
    assert inv.acceptable?
    assert_not inv.expired?

    inv.update!(expires_at: 1.minute.ago)
    assert inv.expired?
    assert_not inv.acceptable?

    inv.update!(expires_at: 1.day.from_now, accepted_at: Time.current)
    assert_not inv.pending?
    assert_not inv.acceptable?
  end

  test "find_acceptable_by_token resolves valid, rejects expired/unknown/accepted" do
    inv = build_invite
    raw = inv.regenerate_token!
    inv.save!

    assert_equal inv, Invitation.find_acceptable_by_token(raw)
    assert_nil Invitation.find_acceptable_by_token("nonsense")
    assert_nil Invitation.find_acceptable_by_token(nil)

    inv.update!(expires_at: 1.minute.ago)
    assert_nil Invitation.find_acceptable_by_token(raw), "expired token is not acceptable"

    inv.update!(expires_at: 1.day.from_now, accepted_at: Time.current)
    assert_nil Invitation.find_acceptable_by_token(raw), "accepted token is not acceptable"
  end

  test "role validation rejects unknown roles" do
    inv = build_invite(role: "superuser")
    inv.regenerate_token!
    assert_not inv.valid?
    assert_includes inv.errors.attribute_names, :role
  end

  test "email is required and must look like an email" do
    bad = build_invite(email: "not-an-email")
    bad.regenerate_token!
    assert_not bad.valid?
    assert_includes bad.errors.attribute_names, :email

    blank = build_invite(email: "")
    blank.regenerate_token!
    assert_not blank.valid?
  end

  test "email is normalized to stripped lowercase" do
    inv = build_invite(email: "  MixedCase@Example.COM  ")
    inv.regenerate_token!
    inv.save!
    assert_equal "mixedcase@example.com", inv.email
  end

  test "only one pending invitation per church and email" do
    first = build_invite
    first.regenerate_token!
    first.save!

    dup = build_invite
    dup.regenerate_token!
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }

    # an accepted row does not block a new pending invite for the same email
    first.update!(accepted_at: Time.current)
    again = build_invite
    again.regenerate_token!
    assert again.save, again.errors.full_messages.to_sentence
  end
end

require "test_helper"

class OffRequestTenantTest < ActiveSupport::TestCase
  setup do
    @central = Church.create!(name: "Central")
    @user = User.create!(church: @central, email: "job@example.com", password: "secret123", role: "editor")
  end

  # Simulates a job/cable path: Current is unset, yet the right church still resolves because
  # it is derived from the explicitly-passed object (design §3.2.3).
  test "resolves church from the passed object without Current" do
    Current.reset
    assert_nil Current.church
    assert_equal @central, OffRequestTenant.church_for(@user)
    assert_nil Current.church, "resolution must not touch Current"
  end

  test "refuses a nil object rather than leaking" do
    Current.reset
    assert_raises(ArgumentError) { OffRequestTenant.church_for(nil) }
  end
end

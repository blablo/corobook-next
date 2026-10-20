require "test_helper"

class ChurchOnlyAdminTest < ActiveSupport::TestCase
  setup do
    @church = Church.create!(name: "Central")
    @admin  = User.create!(church: @church, email: "admin@example.com", password: "secret123", role: "admin")
  end

  test "only_admin? is true when the user is the sole admin" do
    assert @church.only_admin?(@admin)
  end

  test "only_admin? is false when another admin exists" do
    User.create!(church: @church, email: "admin2@example.com", password: "secret123", role: "admin")
    assert_not @church.only_admin?(@admin)
  end

  test "only_admin? is false for an editor" do
    editor = User.create!(church: @church, email: "ed@example.com", password: "secret123", role: "editor")
    assert_not @church.only_admin?(editor)
  end

  test "only_admin? is false for nil" do
    assert_not @church.only_admin?(nil)
  end

  test "admins returns only admin-role users" do
    User.create!(church: @church, email: "ed@example.com", password: "secret123", role: "editor")
    assert_equal [ @admin.id ], @church.admins.pluck(:id)
  end
end

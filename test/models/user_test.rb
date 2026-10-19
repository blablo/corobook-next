require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @central = Church.create!(name: "Central")
    @norte = Church.create!(name: "Norte")
  end

  test "same email can exist in two churches" do
    a = User.create!(church: @central, email: "pastor@example.com", password: "secret123", role: "admin")
    b = User.new(church: @norte, email: "pastor@example.com", password: "secret123", role: "admin")
    assert a.persisted?
    assert b.valid?, b.errors.full_messages.to_sentence
    assert b.save
  end

  test "email is unique within a church" do
    User.create!(church: @central, email: "dup@example.com", password: "secret123", role: "editor")
    dup = User.new(church: @central, email: "dup@example.com", password: "secret123", role: "editor")
    assert_not dup.valid?
  end

  test "password authentication works" do
    user = User.create!(church: @central, email: "auth@example.com", password: "secret123", role: "editor")
    assert user.authenticate("secret123")
    assert_not user.authenticate("wrong")
  end

  test "role enum rejects unknown values via validation" do
    user = User.new(church: @central, email: "role@example.com", password: "secret123")
    user.role = "superadmin"
    assert_not user.valid?
    assert_includes user.errors[:role], "is not included in the list"
  end

  test "role is constrained by a DB check" do
    user = User.create!(church: @central, email: "check@example.com", password: "secret123", role: "editor")
    assert_raises(ActiveRecord::StatementInvalid) do
      User.connection.execute(
        "UPDATE users SET role = 'superadmin' WHERE id = #{user.id}"
      )
    end
  end
end

require "test_helper"

# A named model backed by the existing `users` table, standing in for any church-scoped child
# with a parent. Named (not anonymous) so Rails' validation metadata resolves. It exercises the
# reusable ChurchChild guard (design §3.2) without depending on a feature model from a later phase.
class GuardProbe < ApplicationRecord
  self.table_name = "users"
  include ChurchChild
  attr_accessor :parent
  church_parent :parent
end

class ChurchChildGuardTest < ActiveSupport::TestCase
  setup do
    @central = Church.create!(name: "Central")
    @norte = Church.create!(name: "Norte")
    @parent = User.create!(church: @central, email: "parent@example.com", password: "secret123", role: "admin")
  end

  test "child whose church matches its parent is valid" do
    child = GuardProbe.new(church: @central, parent: @parent, email: "c1@example.com", role: "editor", password_digest: "x")
    assert child.valid?, child.errors.full_messages.to_sentence
  end

  test "child whose church differs from its parent is invalid" do
    child = GuardProbe.new(church: @norte, parent: @parent, email: "c2@example.com", role: "editor", password_digest: "x")
    assert_not child.valid?
    assert_includes child.errors[:church_id], "must match parent's church"
  end
end

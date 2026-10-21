require "test_helper"

class ChurchSubdomainTest < ActiveSupport::TestCase
  setup { @church = Church.create!(name: "Gracia") }

  test "subdomain is optional (nil when blank)" do
    @church.update!(subdomain: "   ")
    assert_nil @church.reload.subdomain
  end

  test "normalizes to lowercase and trims" do
    @church.update!(subdomain: "  Gracia  ")
    assert_equal "gracia", @church.reload.subdomain
  end

  test "accepts a valid label" do
    assert @church.update(subdomain: "grace-church-1")
  end

  test "rejects too short" do
    assert_not @church.update(subdomain: "ab")
    assert @church.errors[:subdomain].any?
  end

  test "rejects invalid characters" do
    assert_not @church.update(subdomain: "my church!")
    assert @church.errors[:subdomain].any?
  end

  test "rejects leading/trailing hyphen" do
    assert_not @church.update(subdomain: "-grace")
    assert_not @church.update(subdomain: "grace-")
  end

  test "rejects a reserved label" do
    assert_not @church.update(subdomain: "www")
    assert_includes @church.errors[:subdomain].to_sentence, "reserved"
  end

  test "enforces uniqueness case-insensitively" do
    @church.update!(subdomain: "gracia")
    other = Church.create!(name: "Other")
    assert_not other.update(subdomain: "GRACIA")
    assert other.errors[:subdomain].any?
  end
end

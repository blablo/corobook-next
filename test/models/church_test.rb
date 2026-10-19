require "test_helper"

class ChurchTest < ActiveSupport::TestCase
  test "valid church persists" do
    church = Church.new(name: "Iglesia Central")
    assert church.save
  end

  test "ccli_license_number is optional" do
    church = Church.new(name: "Iglesia Norte")
    assert church.valid?
    assert_nil church.ccli_license_number
  end

  test "name is required" do
    assert_not Church.new.valid?
  end
end

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

  test "the default template must be one of the church's own templates" do
    church = Church.create!(name: "Central")
    other = Church.create!(name: "Norte")
    service = church.service_sets.create!(name: "Domingo")
    foreign = other.service_sets.create!(name: "Base", template: true)
    template = church.service_sets.create!(name: "Base", template: true)

    assert_not church.update(default_template: service)
    assert_not church.update(default_template: foreign)
    assert church.update(default_template: template)
  end

  test "deleting the default template clears it" do
    church = Church.create!(name: "Central")
    template = church.service_sets.create!(name: "Base", template: true)
    church.update!(default_template: template)
    template.destroy
    assert_nil church.reload.default_template_id
  end
end

require "test_helper"

class HeroSetTest < ActiveSupport::TestCase
  setup do
    @church = Church.create!(name: "Central")
    @other = Church.create!(name: "Norte")
  end

  test "picks the nearest upcoming set by service date" do
    @church.service_sets.create!(name: "Next week", service_date: Date.current + 7)
    soon = @church.service_sets.create!(name: "This Sunday", service_date: Date.current + 1)
    @church.service_sets.create!(name: "Last week", service_date: Date.current - 7)
    assert_equal soon, HeroSet.for(@church)
  end

  test "today counts as upcoming" do
    today = @church.service_sets.create!(name: "Today", service_date: Date.current)
    @church.service_sets.create!(name: "Past", service_date: Date.current - 3)
    assert_equal today, HeroSet.for(@church)
  end

  test "falls back to the most recent set when none is upcoming" do
    @church.service_sets.create!(name: "Old", service_date: Date.current - 30)
    recent = @church.service_sets.create!(name: "Recent", service_date: Date.current - 2)
    assert_equal recent, HeroSet.for(@church)
  end

  test "handles sets with no service date in the fallback (NULLS LAST)" do
    dated = @church.service_sets.create!(name: "Dated past", service_date: Date.current - 5)
    @church.service_sets.create!(name: "Undated", service_date: nil)
    assert_equal dated, HeroSet.for(@church) # a real recent date beats a null
  end

  test "returns nil for a church with no sets" do
    assert_nil HeroSet.for(@church)
  end

  test "is church-scoped — never another church's set" do
    @other.service_sets.create!(name: "Foreign", service_date: Date.current + 1)
    assert_nil HeroSet.for(@church)
  end
end

require "test_helper"

class SetItemTest < ActiveSupport::TestCase
  setup do
    @church = Church.create!(name: "Central")
    @song = @church.songs.create!(title: "Himno", chordpro_source: "[G]Hola")
    @set = @church.service_sets.create!(name: "Domingo")
  end

  test "resolved_title and missing? report a present reference" do
    item = @set.set_items.create!(position: 0, item_type: "song", song: @song)
    assert_equal "Himno", item.resolved_title
    assert_not item.missing?
  end

  # The set_items FKs are RESTRICT, so a reference cannot actually be orphaned (deleting an in-use
  # song raises InvalidForeignKey — covered in ServiceSetTest). missing? is a defensive guard for
  # an out-of-band orphan; stub the association to exercise it.
  test "missing? is true and resolved_title nil when the reference is absent" do
    item = @set.set_items.create!(position: 0, item_type: "song", song: @song)
    item.define_singleton_method(:item) { nil }
    assert item.missing?
    assert_nil item.resolved_title
  end

  test "a library song in a set cannot be deleted (reference cannot dangle)" do
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
    assert_raises(ActiveRecord::InvalidForeignKey) { @song.destroy }
  end
end

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

  test "an empty slot is valid, not missing, and left out of filled" do
    slot = @set.set_items.create!(position: 0, item_type: "text_slide", slot_label: "  Scripture ", slot_tag: " Scripture")
    assert_equal "Scripture", slot.slot_label
    assert_equal "scripture", slot.slot_tag
    assert slot.empty_slot?
    assert_not slot.missing?
    assert_empty @set.set_items.filled
  end

  test "a filled slot keeps its label and counts as filled" do
    slot = @set.set_items.create!(position: 0, item_type: "song", slot_label: "Worship song")
    slot.update!(song: @song)
    assert slot.slot?
    assert_not slot.empty_slot?
    assert_equal [ slot ], @set.set_items.filled.to_a
  end

  test "a slot only takes its own kind" do
    slide = @church.text_slides.create!(title: "Credo", reusable: true)
    slot = @set.set_items.build(position: 0, item_type: "song", slot_label: "Worship song", text_slide: slide)
    assert_not slot.valid?
    assert_includes slot.errors[:base].to_sentence, "song slot takes a song"
  end

  test "the DB accepts an empty slot but not an empty plain item" do
    insert = ->(label) {
      SetItem.connection.execute(
        "INSERT INTO set_items (service_set_id, position, item_type, slot_label, created_at, updated_at) " \
        "VALUES (#{@set.id}, #{SetItem.count}, 'song', #{label ? SetItem.connection.quote(label) : 'NULL'}, now(), now())"
      )
    }
    assert_nothing_raised { insert.call("Worship song") }
    assert_raises(ActiveRecord::StatementInvalid) { insert.call(nil) }
  end

  test "a library song in a set cannot be deleted (reference cannot dangle)" do
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
    assert_raises(ActiveRecord::InvalidForeignKey) { @song.destroy }
  end
end

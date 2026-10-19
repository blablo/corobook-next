require "test_helper"

class ServiceSetTest < ActiveSupport::TestCase
  setup do
    @church = Church.create!(name: "Central")
    @other = Church.create!(name: "Norte")
    @song = @church.songs.create!(title: "Himno", chordpro_source: "[G]Hola")
    @set = @church.service_sets.create!(name: "Domingo")
  end

  test "a set item must reference exactly one item" do
    assert_not SetItem.new(service_set: @set, position: 0, item_type: "song").valid?
    both = SetItem.new(service_set: @set, position: 0, item_type: "song", song: @song,
                       text_slide: @church.text_slides.create!(title: "S", reusable: true))
    assert_not both.valid?
    ok = SetItem.new(service_set: @set, position: 0, item_type: "song", song: @song)
    assert ok.valid?, ok.errors.full_messages.to_sentence
  end

  test "the DB rejects an item with neither or both FKs" do
    assert_raises(ActiveRecord::StatementInvalid) do
      SetItem.connection.execute(
        "INSERT INTO set_items (service_set_id, position, item_type, created_at, updated_at) " \
        "VALUES (#{@set.id}, 0, 'song', now(), now())"
      )
    end
  end

  test "an item referencing another church's song is rejected" do
    foreign_song = @other.songs.create!(title: "Ajeno", chordpro_source: "[C]x")
    item = SetItem.new(service_set: @set, position: 0, item_type: "song", song: foreign_song)
    assert_not item.valid?
    assert_includes item.errors[:base].to_sentence, "same church"
  end

  test "items are returned in position order" do
    s2 = @church.songs.create!(title: "Dos", chordpro_source: "[D]y")
    @set.set_items.create!(position: 1, item_type: "song", song: s2)
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
    assert_equal [ 0, 1 ], @set.set_items.reload.map(&:position)
  end

  test "position is unique within a set" do
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
    dup = @set.set_items.build(position: 0, item_type: "song", song: @song)
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }
  end

  test "deleting a set destroys its inline slides but keeps reusable ones" do
    reusable = @church.text_slides.create!(title: "Credo", reusable: true)
    inline = @church.text_slides.create!(title: "Sermón", reusable: false, set_id: @set.id)
    @set.set_items.create!(position: 0, item_type: "text_slide", text_slide: inline)

    @set.destroy

    assert TextSlide.exists?(reusable.id), "reusable library slide must survive"
    assert_not TextSlide.exists?(inline.id), "inline one-off slide must be reaped"
  end
end

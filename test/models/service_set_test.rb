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

  test "services and templates scopes split sets by the template flag" do
    template = @church.service_sets.create!(name: "Domingo base", template: true)
    assert_equal [ @set ], @church.service_sets.services.to_a
    assert_equal [ template ], @church.service_sets.templates.to_a
  end

  test "copy_items_from references songs and library slides, copies inline slides, and empties slots" do
    template = @church.service_sets.create!(name: "Domingo base", template: true)
    credo = @church.text_slides.create!(title: "Credo", reusable: true)
    welcome = @church.text_slides.create!(title: "Bienvenida", reusable: false, set_id: template.id,
                                          tags: [ "welcome" ], pages: [ { "body_markdown" => "Hola" } ])
    template.set_items.create!(position: 0, item_type: "text_slide", text_slide: welcome)
    template.set_items.create!(position: 1, item_type: "song", song: @song)
    template.set_items.create!(position: 2, item_type: "song", slot_label: "Worship song")
    template.set_items.create!(position: 3, item_type: "text_slide", slot_label: "Scripture", slot_tag: "scripture")
    template.set_items.create!(position: 4, item_type: "text_slide", text_slide: credo)

    @set.copy_items_from(template)
    items = @set.set_items.order(:position).to_a

    assert_equal [ 0, 1, 2, 3, 4 ], items.map(&:position)
    copy = items[0].text_slide
    assert_not_equal welcome.id, copy.id, "inline slide is copied, not shared"
    assert_equal @set.id, copy.set_id
    assert_equal [ "Bienvenida", [ "welcome" ], "Hola" ], [ copy.title, copy.tags, copy.page_markdown ]
    assert_equal @song, items[1].song
    assert items[2].empty_slot?
    assert_equal [ "song", "Worship song" ], [ items[2].item_type, items[2].slot_label ]
    assert_equal [ "Scripture", "scripture" ], [ items[3].slot_label, items[3].slot_tag ]
    assert_equal credo, items[4].text_slide, "library slide is referenced"
    assert_equal 2, @set.empty_slot_count
    assert_equal [ 5, 3 ], [ template.set_items.count, template.set_items.filled.count ], "the template is untouched"
  end

  test "copy_items_from appends after existing items" do
    template = @church.service_sets.create!(name: "Base", template: true)
    template.set_items.create!(position: 0, item_type: "song", slot_label: "Song")
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
    @set.copy_items_from(template)
    assert_equal [ 0, 1 ], @set.set_items.order(:position).pluck(:position)
  end

  test "an inline slide copy reuses the background image blob" do
    template = @church.service_sets.create!(name: "Base", template: true)
    slide = @church.text_slides.create!(title: "Fondo", reusable: false, set_id: template.id)
    slide.background_image.attach(io: File.open(Rails.root.join("test/fixtures/files/bg.png")),
                                  filename: "bg.png", content_type: "image/png")
    copy = slide.copy_for(@set)
    assert_equal slide.background_image.blob, copy.reload.background_image.blob
  end

  test "default_template? is true only for the church's chosen template" do
    template = @church.service_sets.create!(name: "Base", template: true)
    assert_not template.default_template?
    @church.update!(default_template: template)
    assert template.reload.default_template?
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

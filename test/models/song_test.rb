require "test_helper"

class SongTest < ActiveSupport::TestCase
  setup { @church = Church.create!(name: "Central") }

  def build_song(**attrs)
    @church.songs.build({ title: "Himno", chordpro_source: "[G]Hola [C]mundo" }.merge(attrs))
  end

  test "saving derives parsed_lyric and plain_text from the source" do
    song = build_song
    assert song.save
    assert_equal 1, song.parsed_lyric["version"]
    assert_equal "Hola mundo", song.plain_text
  end

  test "a malformed chord does not block the save" do
    song = build_song(chordpro_source: "[Fm#]Hola [G mundo sin cerrar")
    assert song.save, song.errors.full_messages.to_sentence
    assert_equal "unknown", song.copyright_status
  end

  test "title is required" do
    song = build_song(title: nil)
    assert_not song.save
    assert_includes song.errors[:title], "can't be blank"
  end

  test "capo must be within 0..11" do
    assert_not build_song(capo: 12).valid?
    assert_not build_song(capo: -1).valid?
    assert build_song(capo: 5).valid?
  end

  test "the DB rejects an out-of-range capo" do
    song = build_song
    song.save!
    assert_raises(ActiveRecord::StatementInvalid) do
      Song.connection.execute("UPDATE songs SET capo = 20 WHERE id = #{song.id}")
    end
  end

  test "copyright_status defaults to unknown and rejects bad values" do
    assert_equal "unknown", build_song.copyright_status
    song = build_song
    song.copyright_status = "bogus"
    assert_not song.valid?
    song.copyright_status = "copyrighted"
    assert song.valid?
  end

  test "belongs to its church and re-derives on update" do
    song = build_song
    song.save!
    song.update!(chordpro_source: "[D]Nueva letra")
    assert_equal "Nueva letra", song.plain_text
  end
end

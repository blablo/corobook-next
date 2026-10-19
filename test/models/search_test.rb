require "test_helper"

class SearchTest < ActiveSupport::TestCase
  setup do
    @central = Church.create!(name: "Central")
    @norte = Church.create!(name: "Norte")
  end

  test "song search matches a lyric word" do
    @central.songs.create!(title: "Himno", chordpro_source: "Santo [G]santo es el Señor")
    @central.songs.create!(title: "Otro", chordpro_source: "Aleluya")
    results = @central.songs.search("señor")
    assert_equal [ "Himno" ], results.map(&:title)
  end

  test "song search matches title and author" do
    @central.songs.create!(title: "Gracia", author: "Newton", chordpro_source: "x")
    assert_equal 1, @central.songs.search("newton").count
    assert_equal 1, @central.songs.search("graci").count
  end

  test "song search is church scoped" do
    @central.songs.create!(title: "Compartida", chordpro_source: "palabra única")
    @norte.songs.create!(title: "Compartida", chordpro_source: "palabra única")
    assert_equal 1, @central.songs.search("única").count
  end

  test "blank query returns all songs" do
    @central.songs.create!(title: "A", chordpro_source: "x")
    @central.songs.create!(title: "B", chordpro_source: "y")
    assert_equal 2, @central.songs.search("").count
    assert_equal 2, @central.songs.search(nil).count
  end

  test "text slide search matches body and subtype" do
    @central.text_slides.create!(title: "Credo", subtype: "statement_of_faith", body_markdown: "Creo en Dios", reusable: true)
    assert_equal 1, @central.text_slides.search("creo").count
    assert_equal 1, @central.text_slides.search("faith").count
  end

  test "search escapes LIKE wildcards in the query" do
    @central.songs.create!(title: "Normal", chordpro_source: "texto")
    assert_equal 0, @central.songs.search("%").count
  end
end

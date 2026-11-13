require "test_helper"

class ApiV1ImportTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    @other = Church.create!(name: "Other")
    @editor = @church.users.create!(email: "ed@example.com", password: "secret123", role: "editor")
    _, @raw = ApiToken.issue!(user: @editor, name: "test")
  end

  def auth(raw = @raw) = { "Authorization" => "Bearer #{raw}" }
  def json = JSON.parse(response.body)

  test "rejects missing and bad tokens" do
    post "/api/v1/songs", params: { song: { title: "X" } }, as: :json
    assert_response :unauthorized
    post "/api/v1/songs", params: { song: { title: "X" } }, as: :json, headers: auth("nope")
    assert_response :unauthorized
  end

  test "creates a song in the token's church and derives lyrics" do
    assert_difference -> { @church.songs.count }, 1 do
      post "/api/v1/songs", params: { song: { title: "Amazing", song_key: "G",
                                              chordpro_source: "{sov: Verse 1}\n[G]Amazing [C]grace\n{eov}" } },
                            as: :json, headers: auth
    end
    assert_response :created
    assert_includes @church.songs.find(json["song"]["id"]).plain_text, "Amazing grace"
  end

  test "dry run writes nothing" do
    assert_no_difference -> { Song.count } do
      post "/api/v1/songs", params: { dry_run: true, song: { title: "Preview" } }, as: :json, headers: auth
    end
    assert_response :success
    assert json["dry_run"]
  end

  test "duplicate title returns 409 with the existing song" do
    existing = @church.songs.create!(title: "Amazing")
    post "/api/v1/songs", params: { song: { title: "amazing" } }, as: :json, headers: auth
    assert_response :conflict
    assert_equal existing.id, json["existing"]["id"]
  end

  test "a duplicate in another church is not a duplicate" do
    @other.songs.create!(title: "Amazing")
    post "/api/v1/songs", params: { song: { title: "Amazing" } }, as: :json, headers: auth
    assert_response :created
  end

  test "invalid song returns 422" do
    post "/api/v1/songs", params: { song: { title: "" } }, as: :json, headers: auth
    assert_response :unprocessable_entity
  end

  test "search only returns this church's songs" do
    @church.songs.create!(title: "Mine")
    @other.songs.create!(title: "Mine too")
    get "/api/v1/songs", params: { q: "Mine" }, headers: auth
    assert_equal [ "Mine" ], json["songs"].map { |s| s["title"] }
  end

  test "creates a multi-page text slide with tags" do
    post "/api/v1/text_slides", params: { text_slide: { title: "Welcome", tags: [ "Announcement" ],
                                                         pages: [ { body_markdown: "# Hi" }, { body_markdown: "Bye" } ] } },
                                as: :json, headers: auth
    assert_response :created
    assert_equal 2, json["text_slide"]["page_count"]
    assert_equal 1, @church.text_slides.count
  end

  test "duplicate slide title returns 409 and dry run writes nothing" do
    @church.text_slides.create!(title: "Welcome", reusable: true, pages: [ { "body_markdown" => "x" } ])
    post "/api/v1/text_slides", params: { text_slide: { title: "Welcome", pages: [ { body_markdown: "y" } ] } }, as: :json, headers: auth
    assert_response :conflict
    assert_no_difference -> { TextSlide.count } do
      post "/api/v1/text_slides", params: { dry_run: true, text_slide: { title: "New", pages: [ { body_markdown: "y" } ] } }, as: :json, headers: auth
    end
  end

  test "a slide keeps its layout: size, alignment and font" do
    post "/api/v1/text_slides", params: { text_slide: { title: "Creed", font_size: 40, text_align: "left", vertical_align: "top", font: "sans",
                                                         pages: [ { body_markdown: "x" } ] } }, as: :json, headers: auth
    assert_response :created
    slide = @church.text_slides.find(json["text_slide"]["id"])
    assert_equal [ 40, "left", "top", "sans" ], [ slide.font_size, slide.text_align, slide.vertical_align, slide.font ]
  end

  test "an invalid layout value returns 422" do
    post "/api/v1/text_slides", params: { text_slide: { title: "Bad", text_align: "diagonal", pages: [ { body_markdown: "x" } ] } },
                                as: :json, headers: auth
    assert_response :unprocessable_entity
  end

  test "show returns the full song and slide" do
    song = @church.songs.create!(title: "Full", chordpro_source: "{sov: Verse 1}\nHi\n{eov}")
    get "/api/v1/songs/#{song.id}", headers: auth
    assert_equal song.chordpro_source, json["song"]["chordpro_source"]
    slide = @church.text_slides.create!(title: "S", reusable: true, pages: [ { "body_markdown" => "a" } ])
    get "/api/v1/text_slides/#{slide.id}", headers: auth
    assert_equal [ { "body_markdown" => "a" } ], json["text_slide"]["pages"]
  end

  test "patch updates only the fields sent and re-derives lyrics" do
    song = @church.songs.create!(title: "Old", author: "Keep Me", copyright_status: "public_domain", chordpro_source: "{sov: Verse 1}\nold words\n{eov}")
    patch "/api/v1/songs/#{song.id}", params: { song: { chordpro_source: "{sov: Verse 1}\nnew words\n{eov}" } }, as: :json, headers: auth
    assert_response :success
    assert_equal [ "chordpro_source" ], json["changed"]
    song.reload
    assert_equal [ "Keep Me", "public_domain" ], [ song.author, song.copyright_status ]
    assert_includes song.plain_text, "new words"
  end

  test "patch dry run reports changes and writes nothing" do
    slide = @church.text_slides.create!(title: "S", reusable: true, pages: [ { "body_markdown" => "a" } ])
    patch "/api/v1/text_slides/#{slide.id}", params: { dry_run: true, text_slide: { font_size: 40, text_align: "left" } }, as: :json, headers: auth
    assert_response :success
    assert_equal %w[font_size text_align], json["would_change"].sort
    assert_nil slide.reload.font_size
  end

  test "patch replaces slide pages and layout" do
    slide = @church.text_slides.create!(title: "S", reusable: true, pages: [ { "body_markdown" => "a" } ])
    patch "/api/v1/text_slides/#{slide.id}", params: { text_slide: { vertical_align: "top", pages: [ { body_markdown: "x" }, { body_markdown: "y" } ] } },
                                              as: :json, headers: auth
    assert_response :success
    slide.reload
    assert_equal [ "top", 2 ], [ slide.vertical_align, slide.page_count ]
  end

  test "patch refuses a rename onto another title, and invalid values" do
    @church.songs.create!(title: "Taken")
    song = @church.songs.create!(title: "Mine")
    patch "/api/v1/songs/#{song.id}", params: { song: { title: "taken" } }, as: :json, headers: auth
    assert_response :conflict
    patch "/api/v1/songs/#{song.id}", params: { song: { capo: 99 } }, as: :json, headers: auth
    assert_response :unprocessable_entity
    assert_equal "Mine", song.reload.title
  end

  test "patch cannot reach another church's records" do
    other_song = @other.songs.create!(title: "Theirs")
    patch "/api/v1/songs/#{other_song.id}", params: { song: { title: "Hijacked" } }, as: :json, headers: auth
    assert_response :not_found
    get "/api/v1/songs/#{other_song.id}", headers: auth
    assert_response :not_found
    assert_equal "Theirs", other_song.reload.title
  end
end

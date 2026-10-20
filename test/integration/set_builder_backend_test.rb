require "test_helper"

class SetBuilderBackendTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    @other = Church.create!(name: "Norte")
    @editor = User.create!(church: @church, email: "ed@example.com", password: "secret123", role: "editor")
    @song = @church.songs.create!(title: "Himno", song_key: "G", chordpro_source: "[G]Hola")
    @slide = @church.text_slides.create!(title: "Credo", reusable: true)
    @set = @church.service_sets.create!(name: "Domingo")
    post login_path, params: { church_id: @church.id, email: @editor.email, password: "secret123" }
  end

  # ---- 1.2 add_item JSON ----
  test "JSON add of a song returns 201 and the item shape" do
    post add_item_service_set_path(@set),
      params: { kind: "song", song_id: @song.id }, as: :json
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "song", body["kind"]
    assert_equal "Himno", body["title"]
    assert_equal "G", body["key"]
    assert_equal false, body["missing"]
  end

  test "JSON add of an invalid inline slide returns 422 and creates nothing" do
    assert_no_difference -> { @set.set_items.count } do
      post add_item_service_set_path(@set),
        params: { kind: "inline_slide", title: "", body_markdown: "" }, as: :json
    end
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["error"].present?
  end

  test "inline slide is created with tags and a single page" do
    assert_difference -> { @set.set_items.count }, 1 do
      post add_item_service_set_path(@set),
        params: { kind: "inline_slide", title: "Announcement",
                  tags: [ "notice", "welcome" ], body_markdown: "Hello" }, as: :json
    end
    assert_response :created
    slide = @set.set_items.order(:position).last.text_slide
    assert_equal "Announcement", slide.title
    assert_equal %w[notice welcome], slide.tags
    assert_equal "Hello", slide.pages.first["body_markdown"]
    assert_not slide.reusable?
  end

  test "adding another church's song is rejected" do
    foreign = @other.songs.create!(title: "Ajeno", chordpro_source: "[C]x")
    assert_no_difference -> { @set.set_items.count } do
      post add_item_service_set_path(@set), params: { kind: "song", song_id: foreign.id }, as: :json
    end
    assert_response :not_found
  end

  test "HTML add still redirects (no-JS fallback)" do
    post add_item_service_set_path(@set), params: { kind: "song", song_id: @song.id }
    assert_redirected_to @set
  end

  # ---- 1.3 reorder stale guard ----
  test "valid reorder persists order and returns 204" do
    a = @set.set_items.create!(position: 0, item_type: "song", song: @song)
    s2 = @church.songs.create!(title: "Dos", chordpro_source: "[D]y")
    b = @set.set_items.create!(position: 1, item_type: "song", song: s2)
    patch reorder_service_set_path(@set), params: { ordered_ids: [ b.id, a.id ] }, as: :json
    assert_response :no_content
    assert_equal [ b.id, a.id ], @set.set_items.reload.order(:position).map(&:id)
  end

  test "a stale reorder (ids != membership) returns 409 and does not change positions" do
    a = @set.set_items.create!(position: 0, item_type: "song", song: @song)
    before = @set.set_items.order(:position).map(&:id)
    patch reorder_service_set_path(@set), params: { ordered_ids: [ a.id, 999_999 ] }, as: :json
    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "stale", body["error"]
    assert body["items"].is_a?(Array)
    assert_equal before, @set.set_items.reload.order(:position).map(&:id)
  end

  # ---- 1.4 remove_item JSON ----
  test "JSON remove returns 204 and deletes the item; reusable slide survives" do
    item = @set.set_items.create!(position: 0, item_type: "text_slide", text_slide: @slide)
    delete remove_item_service_set_path(@set, item_id: item.id), as: :json
    assert_response :no_content
    assert_not SetItem.exists?(item.id)
    assert TextSlide.exists?(@slide.id), "reusable library slide must survive detach"
  end

  test "removing an inline-slide item reaps the slide" do
    inline = @church.text_slides.create!(title: "Sermón", reusable: false, set_id: @set.id)
    item = @set.set_items.create!(position: 0, item_type: "text_slide", text_slide: inline)
    delete remove_item_service_set_path(@set, item_id: item.id), as: :json
    assert_response :no_content
    assert_not TextSlide.exists?(inline.id), "inline one-off slide must be reaped"
  end

  # ---- 1.5 library search ----
  test "song library search filters by title and is church-scoped, capped at 20" do
    @other.songs.create!(title: "Himno ajeno", chordpro_source: "[C]x")
    get library_service_set_path(@set), params: { kind: "song", q: "Himno" }, as: :json
    assert_response :success
    rows = JSON.parse(response.body)
    titles = rows.map { |r| r["title"] }
    assert_includes titles, "Himno"
    assert_not_includes titles, "Himno ajeno"
    assert rows.size <= 20
  end

  test "slide library search returns only reusable slides" do
    @church.text_slides.create!(title: "Inline uno", reusable: false, set_id: @set.id)
    get library_service_set_path(@set), params: { kind: "slide", q: "" }, as: :json
    assert_response :success
    titles = JSON.parse(response.body).map { |r| r["title"] }
    assert_includes titles, "Credo"
    assert_not_includes titles, "Inline uno"
  end

  test "the New Set form defaults the date to next Sunday and the name to that date" do
    get new_service_set_path
    assert_response :success
    sunday = Date.current + ((7 - Date.current.wday) % 7)
    assert_select "input[data-role=set-date][value=?]", sunday.to_s
    assert_select "input[data-role=set-name][value=?]", sunday.strftime("%A, %b %-d")
  end
end

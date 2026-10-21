require "test_helper"

class ServiceSetPreviewTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    @editor = @church.users.create!(email: "ed@example.com", password: "secret123", role: "editor")
    @admin = @church.users.create!(email: "admin@example.com", password: "secret123", role: "admin")
    @song = @church.songs.create!(title: "Himno", song_key: "G",
      chordpro_source: "{key: G}\n{soc: Chorus}\n[G]Hola [C]mundo\n{eoc}", arrangement: [ "Chorus" ])
    @slide = @church.text_slides.create!(title: "Aviso", reusable: true,
      pages: [ { "body_markdown" => "Bienvenidos" } ])
    @set = @church.service_sets.create!(name: "Domingo")
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
    @set.set_items.create!(position: 1, item_type: "text_slide", text_slide: @slide)
  end

  def login(user)
    post login_path, params: { church_id: @church.id, email: user.email, password: "secret123" }
  end

  test "the preview page shows the whole set in order" do
    login(@editor)
    get preview_service_set_path(@set)
    assert_response :success
    assert_select "[data-role=set-preview]"
    # Title slide + chorus for the song, then the slide.
    assert_select "[data-role=chart-title]", text: /Himno/
    assert_select "[data-role=section-label]", text: /Chorus/
    assert_select "[data-role=chord]", text: "G"
    assert_select "[data-role=musician-slide]", text: /Bienvenidos/
  end

  test "the preview honors a viewer's chosen key" do
    login(@editor)
    get preview_service_set_path(@set, key: "A")
    assert_response :success
    assert_select "[data-role=chord]", text: "A"
    assert_select "[data-role=key-badge]", text: "Key A"
  end

  test "an admin can view the read-only preview" do
    login(@admin)
    get preview_service_set_path(@set)
    assert_response :success
    assert_select "[data-role=set-preview]"
  end

  test "the set show page links to the preview" do
    login(@editor)
    get service_set_path(@set)
    assert_response :success
    assert_select "[data-role=preview-set][href='#{preview_service_set_path(@set)}']"
  end
end

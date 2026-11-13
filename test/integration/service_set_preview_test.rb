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
    # One numbered card per item: the song with its sections and chords, then the slide.
    assert_select "[data-role=preview-item]", count: 2
    assert_select "[data-role=preview-item]:nth-of-type(1) [data-role=chart-title]", text: /Himno/
    assert_select "[data-role=section-label]", text: /Chorus/
    assert_select "[data-role=chord]", text: "G"
    assert_select "[data-role=preview-item]:nth-of-type(2) [data-role=musician-slide]", text: /Bienvenidos/
    assert_select "[data-role=set-summary]", text: /Band preview · No date set · 2 items/
  end

  test "each text slide shows its title as a header in the preview" do
    login(@editor)
    get preview_service_set_path(@set)
    assert_response :success
    assert_select "[data-role=slide-title]", text: /Aviso/
  end

  test "a multi-page slide is one card, with each page's text under a page label" do
    @slide.update!(pages: [ { "body_markdown" => "uno" }, { "body_markdown" => "dos" } ])
    login(@editor)
    get preview_service_set_path(@set)
    assert_response :success
    assert_select "[data-role=slide-title]", count: 1
    assert_select "[data-role=slide-pages]", text: "2 pages"
    assert_select "[data-role=musician-slide]", count: 2
    assert_select "[data-role=musician-slide] [data-role=slide-page]", text: "Page 1"
    assert_select "[data-role=musician-slide]", text: /Page 2\s*dos/
  end

  test "the preview honors a viewer's chosen key" do
    login(@editor)
    get preview_service_set_path(@set, key: "A")
    assert_response :success
    assert_select "[data-role=chord]", text: "A"
    assert_select "[data-role=key-badge]", text: "Key A"
  end

  test "Transpose steps the whole service a semitone at a time, and Print keeps it" do
    login(@editor)
    get preview_service_set_path(@set, semitones: 2)
    assert_response :success
    assert_select "[data-role=chord]", text: "A"
    assert_select "[data-role=transpose-value]", text: "+2"
    assert_select "[data-role=transpose-up][href=?]", preview_service_set_path(@set, semitones: 3)
    assert_select "[data-role=transpose-down][href=?]", preview_service_set_path(@set, semitones: 1)
    assert_select "[data-role=print][href=?]", print_service_set_path(@set, semitones: 2)
  end

  test "a capo shows chord shapes for it, and the key badge says so" do
    login(@editor)
    get preview_service_set_path(@set, capo: 2)
    assert_response :success
    assert_select "[data-role=chord]", text: "F" # G played with capo 2
    assert_select "[data-role=key-badge]", text: "Key G · Capo 2"
    assert_select "select[data-role=capo] option[selected][value='2']"
  end

  test "the order beside the cards jumps to each item" do
    login(@editor)
    get preview_service_set_path(@set)
    items = @set.set_items.order(:position)
    assert_select "[data-role=preview-contents] [data-role=contents-link]", count: 2
    assert_select "[data-role=contents-link][href='#item-#{items.first.id}']", text: /Himno\s*G/
    assert_select "section#item-#{items.second.id}[data-role=preview-item]"
  end

  test "the date reads in the viewer's language" do
    @set.update!(service_date: Date.new(2026, 10, 25))
    @editor.update!(locale: "es")
    login(@editor)
    get preview_service_set_path(@set)
    assert_select "[data-role=set-summary]", text: /domingo 25 de octubre · 2 elementos/
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

  test "the print view renders a standalone band chart with songs and slides" do
    login(@editor)
    get print_service_set_path(@set)
    assert_response :success
    # Standalone layout: no admin shell navbar/sidebar.
    assert_select "header.navbar", count: 0
    assert_select "[data-role=sidebar]", count: 0
    # The song and its chords, plus the slide and its title.
    assert_select ".song-title", text: /Himno/
    assert_select ".musician-chord", text: "G"
    assert_select ".slide-title", text: /Aviso/
  end

  test "the print view honors a viewer's chosen key" do
    login(@editor)
    get print_service_set_path(@set, key: "A")
    assert_response :success
    assert_select ".musician-chord", text: "A"
  end

  test "an admin can open the read-only print view" do
    login(@admin)
    get print_service_set_path(@set)
    assert_response :success
    assert_select ".song-title", text: /Himno/
  end

  test "the preview links to the print view" do
    login(@editor)
    get preview_service_set_path(@set)
    assert_response :success
    assert_select "a[href^='#{print_service_set_path(@set)}']"
  end
end

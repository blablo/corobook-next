require "test_helper"

class SlidePdfImportTest < ActionDispatch::IntegrationTest
  Importer = Corobook::PdfSlideImporter

  setup do
    @church = Church.create!(name: "Central")
    @editor = @church.users.create!(email: "ed@example.com", password: "secret123", role: "editor")
    @original_rasterizer = Importer.rasterizer
    Importer.rasterizer = lambda do |_pdf, dir|
      (1..2).map { |i| File.join(dir, "page-#{i}.jpg").tap { |p| FileUtils.cp(file_fixture("bg.png"), p) } }
    end
  end

  teardown { Importer.rasterizer = @original_rasterizer }

  def login
    post login_path, params: { church_id: @church.id, email: @editor.email, password: "secret123" }
  end

  def pdf = fixture_file_upload("two_pages.pdf", "application/pdf")

  test "the library links to the import page" do
    login
    get text_slides_path
    assert_select "a[data-role=import-slides][href='#{import_text_slides_path}']"
    get import_text_slides_path
    assert_response :success
    assert_select "[data-role=slide-import-form] input[type=file][name=pdf]"
  end

  test "importing a PDF creates an image slide and opens it" do
    login
    assert_difference -> { @church.text_slides.count }, 1 do
      post import_text_slides_path, params: { title: "Anuncios", pdf: pdf }
    end
    slide = @church.text_slides.last
    assert_redirected_to text_slide_path(slide)
    follow_redirect!
    assert_select "[data-role=flash-notice]", text: /2 pages/
    assert_select "[data-role=deck-page-image]", count: 2
  end

  test "a non-PDF upload shows an error and creates nothing" do
    login
    assert_no_difference -> { @church.text_slides.count } do
      post import_text_slides_path, params: { pdf: fixture_file_upload("bg.png", "application/pdf") }
    end
    assert_response :unprocessable_entity
    assert_select "[data-role=flash-alert]", text: /isn't a PDF/
  end

  test "signed-out users cannot import" do
    post import_text_slides_path, params: { pdf: pdf }
    assert_redirected_to login_path
  end

  test "an imported slide plays page by page on the projector and shows images to musicians" do
    slide = Importer.call(church: @church, file: pdf, title: "Deck")
    set = @church.service_sets.create!(name: "Domingo")
    item = set.set_items.create!(position: 0, item_type: "text_slide", text_slide: slide)
    session = LiveSession.launch(set)
    session.update!(current_set_item_id: item.id, current_section_index: 1)

    get projector_path(session.projector_token)
    assert_select "[data-role=projector-slide][data-imported=true] img[src*='page-2.jpg']"

    get musician_path(session.musician_token)
    # Every page in the full list, plus the current page in the live "Now" band.
    assert_select "[data-role=set-list] [data-role=musician-slide] img", count: 2
    assert_select "[data-role=now-bar] [data-role=musician-slide] img[src*='page-2.jpg']"
  end

  test "the edit page hides the text editor for an imported slide and keeps its pages on save" do
    slide = Importer.call(church: @church, file: pdf, title: "Deck")
    login
    get edit_text_slide_path(slide)
    assert_select "[data-role=imported-note]"
    assert_select "[data-role=imported-pages] img", count: 2

    patch text_slide_path(slide), params: { text_slide: { title: "Renamed", pages: [ { body_markdown: "" }, { body_markdown: "" } ] } }
    slide.reload
    assert_equal "Renamed", slide.title
    assert_equal 2, slide.page_count
    assert slide.imported?
  end
end

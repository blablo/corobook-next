require "test_helper"

class SlideArchiveTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    @editor = @church.users.create!(email: "ed@example.com", password: "secret123", role: "editor")
    @active = @church.text_slides.create!(title: "Bienvenida", tags: [ "anuncio" ], pages: [ { "body_markdown" => "Hola" } ])
    @old = @church.text_slides.create!(title: "Campaña 2025", tags: [ "viejo" ], pages: [ { "body_markdown" => "Pasado" } ],
                                       archived_at: 2.days.ago)
    @set = @church.service_sets.create!(name: "Domingo")
  end

  def login
    post login_path, params: { church_id: @church.id, email: @editor.email, password: "secret123" }
  end

  test "archived slides are hidden from the library, its tags and the home count" do
    login
    get text_slides_path
    assert_select "[data-role=slide-results]", text: /Bienvenida/
    assert_select "[data-role=slide-results]", text: /Campaña 2025/, count: 0
    assert_select "[data-role=tag-filter]", text: /viejo/, count: 0
    assert_select "a[data-role=archived-link][href='#{archived_text_slides_path}']", text: /\(1\)/

    get text_slides_path(q: "Campaña")
    assert_select "[data-role=slide-results]", text: /Campaña 2025/, count: 0

    get root_path
    assert_not_includes response.body, "Campaña 2025"
  end

  test "archived slides are not offered in the service builder" do
    login
    get library_service_set_path(@set, kind: "slide", q: ""), headers: { "Accept" => "application/json" }
    titles = response.parsed_body.map { |r| r["title"] }
    assert_includes titles, "Bienvenida"
    assert_not_includes titles, "Campaña 2025"

    get service_set_path(@set)
    assert_select "select[name=text_slide_id] option", text: "Campaña 2025", count: 0
  end

  test "the archived page lists only archived slides" do
    login
    get archived_text_slides_path
    assert_response :success
    assert_select "[data-role=archived-results]", text: /Campaña 2025/
    assert_select "[data-role=archived-results]", text: /Bienvenida/, count: 0
  end

  test "archive and restore round-trip" do
    login
    patch archive_text_slide_path(@active)
    assert_redirected_to text_slides_path
    assert @active.reload.archived?

    get text_slide_path(@active)
    assert_select "[data-role=archived-badge]"
    assert_select "[data-role=unarchive-slide]"

    patch unarchive_text_slide_path(@active)
    assert_redirected_to archived_text_slides_path
    assert_not @active.reload.archived?
  end

  test "a service that already uses an archived slide still projects it" do
    item = @set.set_items.create!(position: 0, item_type: "text_slide", text_slide: @old)
    session = LiveSession.launch(@set)
    session.update!(current_set_item_id: item.id, current_section_index: 0)
    get projector_path(session.projector_token)
    assert_select "[data-role=projector-slide]", text: /Pasado/
  end

  test "each library row can be archived, keeping the current filter" do
    login
    get text_slides_path(tag: "anuncio")
    assert_select "[data-role=slide-results] form[action='#{archive_text_slide_path(@active, tag: 'anuncio')}'] [data-role=archive-slide]"

    patch archive_text_slide_path(@active, tag: "anuncio")
    assert_redirected_to text_slides_path(tag: "anuncio")
    assert @active.reload.archived?
  end

  test "signed-out users cannot archive" do
    patch archive_text_slide_path(@active)
    assert_redirected_to login_path
    assert_not @active.reload.archived?
  end
end

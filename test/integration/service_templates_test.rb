require "test_helper"

class ServiceTemplatesTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @church = Church.create!(name: "Central")
    @other = Church.create!(name: "Norte")
    @editor = User.create!(church: @church, email: "ed@example.com", password: "secret123", role: "editor")
    @song = @church.songs.create!(title: "Himno", song_key: "G", chordpro_source: "[G]Hola")
    @psalm = @church.text_slides.create!(title: "Salmo 23", reusable: true, tags: [ "scripture" ])
    @credo = @church.text_slides.create!(title: "Credo", reusable: true)
    @template = @church.service_sets.create!(name: "Domingo base", template: true)
    @template.set_items.create!(position: 0, item_type: "song", slot_label: "Worship song")
    @template.set_items.create!(position: 1, item_type: "text_slide", slot_label: "Scripture", slot_tag: "scripture")
    @template.set_items.create!(position: 2, item_type: "text_slide", text_slide: @credo)
    post login_path, params: { church_id: @church.id, email: @editor.email, password: "secret123" }
  end

  # ---- Services page ----
  test "templates are listed in the Templates card, apart from the services" do
    @church.service_sets.create!(name: "Domingo 9", service_date: Date.current + 3)
    get service_sets_path
    assert_select "[data-role=next-service]", text: /Domingo 9/
    assert_select "[data-role=upcoming-sets]", text: /Domingo base/, count: 0
    assert_select "[data-role=tab-templates]", count: 0

    assert_select "[data-role=templates-card] [data-role=template-row]", 1
    assert_select "[data-role=template-row] [data-role=template-link][href='#{service_set_path(@template)}']", text: "Domingo base"
    assert_select "[data-role=template-row]", text: /1 song slot · 1 slide slot/
    assert_select "[data-role=template-row] [data-role=use-template][href='#{new_service_set_path(from_template_id: @template.id)}']"
    assert_select "[data-role=templates-card] [data-role=new-template][href='#{new_service_set_path(template: 1)}']"

    get service_sets_path(tab: "past")
    assert_select "[data-role=templates-card] [data-role=template-row]", 1
  end

  test "the Templates card explains templates when there are none" do
    @template.destroy
    get service_sets_path
    assert_select "[data-role=templates-card] [data-role=templates-empty] [data-role=new-template]"
    assert_select "[data-role=template-row]", count: 0
  end

  test "the default template is marked in the Templates card" do
    @church.update!(default_template: @template)
    get service_sets_path
    assert_select "[data-role=template-row] [data-role=default-badge]"
  end

  # ---- Creating templates and services ----
  test "creating a template stores no date and opens the template editor" do
    get new_service_set_path(template: 1)
    assert_select "input[name='service_set[template]'][value='1']"
    assert_select "[data-role=set-date]", count: 0

    post service_sets_path, params: { service_set: { name: "Noche", template: "1", service_date: "2026-12-01" } }
    template = @church.service_sets.find_by!(name: "Noche")
    assert template.template?
    assert_nil template.service_date
    assert_redirected_to service_set_path(template)

    follow_redirect!
    assert_select "[data-role=template-header]"
    assert_select "[data-role=tab-slots]"
    assert_select "[data-role=launch]", count: 0
    assert_select "[data-role=send-to-band]", count: 0
  end

  test "the new service form starts from the default template" do
    blank = @church.service_sets.create!(name: "Especial", template: true)
    @church.update!(default_template: @template)
    get new_service_set_path
    assert_select "[data-role=start-from] option[selected][value='#{@template.id}']"
    assert_select "[data-role=start-from] option[value='#{blank.id}']"
    assert_select "[data-role=start-from] option[value='']"

    get new_service_set_path(from_template_id: blank.id)
    assert_select "[data-role=start-from] option[selected][value='#{blank.id}']"
  end

  test "a service created from a template copies its items with empty slots" do
    post service_sets_path, params: { service_set: { name: "Domingo 16", service_date: "2026-11-16" },
                                      from_template_id: @template.id }
    service = @church.service_sets.services.find_by!(name: "Domingo 16")
    assert_redirected_to service_set_path(service)
    items = service.set_items.order(:position).to_a
    assert_equal [ "Worship song", "Scripture", nil ], items.map(&:slot_label)
    assert_equal [ true, true, false ], items.map(&:empty_slot?)
    assert_equal @credo, items[2].text_slide
  end

  test "a blank service or another church's template copies nothing" do
    foreign = @other.service_sets.create!(name: "Ajena", template: true)
    foreign.set_items.create!(position: 0, item_type: "song", slot_label: "Canción")

    post service_sets_path, params: { service_set: { name: "A", service_date: "2026-11-16" }, from_template_id: "" }
    post service_sets_path, params: { service_set: { name: "B", service_date: "2026-11-16" }, from_template_id: foreign.id }
    assert_equal 0, SetItem.joins(:service_set).where(service_sets: { name: %w[A B] }).count
  end

  test "updating a template keeps it dateless" do
    patch service_set_path(@template), params: { service_set: { name: "Domingo AM", service_date: "2026-12-01" } }
    @template.reload
    assert_equal "Domingo AM", @template.name
    assert_nil @template.service_date
  end

  test "Make default toggles the church's default template" do
    patch toggle_default_service_set_path(@template)
    assert_equal @template.id, @church.reload.default_template_id
    follow_redirect!
    assert_select "[data-role=template-header] [data-role=default-badge]"

    patch toggle_default_service_set_path(@template)
    assert_nil @church.reload.default_template_id
  end

  test "a service cannot be made the default template" do
    service = @church.service_sets.create!(name: "Domingo")
    patch toggle_default_service_set_path(service)
    assert_nil @church.reload.default_template_id
  end

  test "deleting a template returns to the Templates tab and clears the default" do
    @church.update!(default_template: @template)
    delete service_set_path(@template)
    assert_redirected_to service_sets_path
    assert_nil @church.reload.default_template_id
    assert TextSlide.exists?(@credo.id), "a library slide in the template survives"
  end

  # ---- Adding slots ----
  test "adding a song slot and a slide slot answers with the rendered row" do
    post add_item_service_set_path(@template), params: { kind: "song_slot", slot_label: "Response song" }, as: :json
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal [ "song", "Response song", true ], body.values_at("kind", "slot_label", "empty_slot")
    assert_includes body["html"], "Response song"
    assert_includes body["html"], "data-empty-slot=\"true\""

    post add_item_service_set_path(@template), params: { kind: "slide_slot", slot_tag: " Sermon_Notes " }, as: :json
    body = JSON.parse(response.body)
    assert_equal [ "text_slide", "sermon_notes", "Sermon notes" ], body.values_at("kind", "slot_tag", "slot_label")
  end

  test "a song slot without a name gets a default label; a slide slot needs a tag" do
    post add_item_service_set_path(@template), params: { kind: "song_slot", slot_label: "" }, as: :json
    assert_equal "Song", JSON.parse(response.body)["slot_label"]

    assert_no_difference -> { @template.set_items.count } do
      post add_item_service_set_path(@template), params: { kind: "slide_slot", slot_tag: " " }, as: :json
    end
    assert_response :bad_request
  end

  test "the template editor shows slots and offers the church's slide tags" do
    get service_set_path(@template)
    assert_select "[data-role=slot-badge]", 2
    assert_select "[data-role=slot-tags] [data-tag=scripture]"
    assert_select "[data-role=choose-slot]", count: 0
  end

  # ---- Filling slots ----
  def service_from_template
    @church.service_sets.create!(name: "Domingo 16", service_date: Date.current + 4).tap { |s| s.copy_items_from(@template) }
  end

  test "a service shows its empty slots, the slots-to-fill badge and Choose buttons" do
    service = service_from_template
    get service_set_path(service)
    assert_select "[data-role=slots-to-fill]", text: "2 slots to fill"
    assert_select "[data-role=choose-slot]", 2
    assert_select "[data-role=choose-slot][data-slot-kind=slide][data-slot-tag=scripture]", text: "Choose a scripture slide"
    assert_select "[data-role=go-live-empty-modal]", text: /2 slots are still empty/
  end

  test "filling a song slot and a slide slot" do
    service = service_from_template
    song_slot, slide_slot = service.set_items.order(:position).first(2)

    patch fill_item_service_set_path(service, item_id: song_slot.id), params: { song_id: @song.id }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ "Himno", false ], body.values_at("title", "empty_slot")
    assert_includes body["html"], "data-role=\"change-slot\""

    patch fill_item_service_set_path(service, item_id: slide_slot.id), params: { text_slide_id: @psalm.id }, as: :json
    assert_response :success
    assert_equal @psalm, slide_slot.reload.text_slide
    assert_equal "Scripture", slide_slot.slot_label, "a filled slot keeps its label"
    assert_equal 0, service.reload.empty_slot_count
  end

  test "a slot only takes its own kind from this church's library" do
    service = service_from_template
    song_slot, slide_slot = service.set_items.order(:position).first(2)
    foreign_song = @other.songs.create!(title: "Ajeno", chordpro_source: "[C]x")
    archived = @church.text_slides.create!(title: "Viejo", reusable: true, archived_at: Time.current)

    patch fill_item_service_set_path(service, item_id: song_slot.id), params: { text_slide_id: @psalm.id }, as: :json
    assert_response :not_found
    patch fill_item_service_set_path(service, item_id: song_slot.id), params: { song_id: foreign_song.id }, as: :json
    assert_response :not_found
    patch fill_item_service_set_path(service, item_id: slide_slot.id), params: { text_slide_id: archived.id }, as: :json
    assert_response :not_found
    assert_equal 2, service.reload.empty_slot_count
  end

  test "a regular item cannot be filled" do
    service = service_from_template
    fixed = service.set_items.order(:position).last
    patch fill_item_service_set_path(service, item_id: fixed.id), params: { text_slide_id: @psalm.id }, as: :json
    assert_response :not_found
    assert_equal @credo, fixed.reload.text_slide
  end

  test "the slot picker lists only slides with the slot's tag and when they were last used" do
    @church.text_slides.create!(title: "Salmo 1", reusable: true, tags: [ "other" ])
    past = @church.service_sets.create!(name: "Pasado", service_date: Date.new(2026, 10, 26))
    past.set_items.create!(position: 0, item_type: "text_slide", text_slide: @psalm)

    get library_service_set_path(@template), params: { kind: "slide", q: "salmo", tag: "scripture", slot: 1 }
    rows = JSON.parse(response.body)
    assert_equal [ "Salmo 23" ], rows.map { |r| r["title"] }
    assert_equal "last used Oct 26", rows.first["subtitle"]

    get library_service_set_path(@template), params: { kind: "song", slot: 1 }
    assert_equal "never used", JSON.parse(response.body).first["subtitle"]

    get library_service_set_path(@template), params: { kind: "slide", q: "salmo" }
    assert_equal [ "Salmo 1", "Salmo 23" ], JSON.parse(response.body).map { |r| r["title"] }
    assert_nil JSON.parse(response.body).first["subtitle"], "the main picker skips the last-used lookup"
  end

  test "another church's template cannot be made the default, and another service's slot cannot be filled" do
    foreign = @other.service_sets.create!(name: "Ajena", template: true)
    patch toggle_default_service_set_path(foreign)
    assert_response :not_found

    service = service_from_template
    other_service = service_from_template
    slot = other_service.set_items.order(:position).first
    patch fill_item_service_set_path(service, item_id: slot.id), params: { song_id: @song.id }, as: :json
    assert_response :not_found
    assert slot.reload.empty_slot?
  end

  test "removing an empty slot from a service" do
    service = service_from_template
    slot = service.set_items.order(:position).first
    delete remove_item_service_set_path(service, item_id: slot.id), as: :json
    assert_response :no_content
    assert_equal 1, service.reload.empty_slot_count
  end

  # ---- Live ----
  test "a template can never go live" do
    assert_no_difference -> { LiveSession.count } do
      post launch_service_set_path(@template)
    end
    assert_redirected_to service_set_path(@template)
    assert flash[:alert].present?
  end

  test "a service with only empty slots cannot go live" do
    service = @church.service_sets.create!(name: "Vacío")
    service.set_items.create!(position: 0, item_type: "song", slot_label: "Song")
    assert_no_difference -> { LiveSession.count } do
      post launch_service_set_path(service)
    end
    get service_set_path(service)
    assert_select "[data-role=launch].btn-disabled"
  end

  test "a service with empty slots goes live from its first filled item" do
    service = service_from_template
    post launch_service_set_path(service)
    session = service.live_sessions.find_by!(status: "active")
    assert_equal @credo, session.current_set_item.text_slide
  end

  test "lists send a service with empty slots to its page instead of going live" do
    service = service_from_template
    get service_sets_path
    assert_select "[data-role=next-service] [data-role=set-fill-slots]", text: "Fill 2 slots"
    assert_select "[data-role=upcoming-sets] [data-role=set-status][data-status=slots]", text: "2 slots to fill"
    assert_select "form[action='#{launch_service_set_path(service)}']", count: 0

    get root_path
    assert_select "[data-role=fill-slots]", text: "Fill 2 slots"
    assert_select "[data-role=recent-sets] [data-role=set-status][data-status=slots]", text: "2 slots to fill"
    assert_select "[data-role=recent-sets] [data-role=set-open][href='#{service_set_path(service)}']"
    assert_select "form[action='#{launch_service_set_path(service)}']", count: 0
  end

  test "home leaves templates out of the hero, recent services and the count" do
    get root_path
    assert_response :success
    assert_select "body", text: /Domingo base/, count: 0
  end

  test "a template is not sent to the band" do
    User.create!(church: @church, email: "band@example.com", password: "secret123", role: "editor", band_member: true)
    assert_no_enqueued_emails do
      post send_to_band_service_set_path(@template)
    end
  end
end

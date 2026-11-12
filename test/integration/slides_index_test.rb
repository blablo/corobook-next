require "test_helper"

class SlidesIndexTest < ActionDispatch::IntegrationTest
  setup do
    @church = Church.create!(name: "Central")
    @admin = User.create!(church: @church, email: "admin@example.com", password: "secret123", role: "admin")
    post login_path, params: { church_id: @church.id, email: @admin.email, password: "secret123" }
  end

  test "each library slide is a card with a projector thumbnail of its first page" do
    slide = @church.text_slides.create!(title: "Bienvenida", tags: [ "anuncio" ], reusable: true,
      pages: [ { "body_markdown" => "Hola" }, { "body_markdown" => "Adiós" } ])

    get text_slides_path
    assert_select "[data-role=slide-results] [data-role=slide-card]", count: 1 do
      assert_select ".projector-preview [data-role=projector-slide]", text: /Hola/
      assert_select ".projector-preview", text: /Adiós/, count: 0
      assert_select "a[href='#{text_slide_path(slide)}']", text: "Bienvenida"
      assert_select ".badge", text: "2 pages"
      assert_select "a.badge[href='#{text_slides_path(tag: "anuncio")}']"
    end
  end

  test "a search with no matches offers to clear the filters; an empty library offers create and import" do
    @church.text_slides.create!(title: "Bienvenida", reusable: true, pages: [ { "body_markdown" => "Hola" } ])
    get text_slides_path(q: "zzz")
    assert_select "[data-role=slide-results] a[href='#{text_slides_path}']"

    @church.text_slides.destroy_all
    get text_slides_path
    assert_select "[data-role=slide-results] a[href='#{new_text_slide_path}']"
    assert_select "[data-role=slide-results] a[href='#{import_text_slides_path}']"
  end
end

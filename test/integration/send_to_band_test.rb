require "test_helper"

class SendToBandTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @church = Church.create!(name: "Central")
    @other  = Church.create!(name: "Norte")
    @editor = @church.users.create!(email: "ed@example.com", password: "secret123", role: "editor")
    @drums  = @church.users.create!(email: "drums@example.com", password: "secret123", role: "editor", band_member: true)
    @keys   = @church.users.create!(email: "keys@example.com", password: "secret123", role: "admin", band_member: true)
    @not_band = @church.users.create!(email: "tech@example.com", password: "secret123", role: "editor")
    @song = @church.songs.create!(title: "Himno", song_key: "G",
      chordpro_source: "{soc: Chorus}\n[G]Hola\n{eoc}")
    @set = @church.service_sets.create!(name: "Domingo")
    @set.set_items.create!(position: 0, item_type: "song", song: @song)
  end

  def login(user)
    post login_path, params: { church_id: user.church_id, email: user.email, password: "secret123" }
  end

  test "emails each band member separately and nobody else" do
    login(@editor)
    assert_enqueued_emails 2 do
      post send_to_band_service_set_path(@set)
    end
    assert_redirected_to service_set_path(@set)
    follow_redirect!
    assert_select "[data-role=flash-notice]", text: /2 band members/

    perform_enqueued_jobs
    recipients = ActionMailer::Base.deliveries.map(&:to).flatten
    assert_equal %w[drums@example.com keys@example.com], recipients.sort
    assert ActionMailer::Base.deliveries.all? { |m| m.to.size == 1 && m.reply_to == [ "ed@example.com" ] }
  end

  test "another church's band members are never emailed" do
    @other.users.create!(email: "x@other.com", password: "secret123", role: "editor", band_member: true)
    login(@editor)
    post send_to_band_service_set_path(@set)
    perform_enqueued_jobs
    assert_not_includes ActionMailer::Base.deliveries.map(&:to).flatten, "x@other.com"
  end

  test "no band members: nothing is sent and the editor is told why" do
    @church.users.update_all(band_member: false)
    login(@editor)
    assert_no_enqueued_emails { post send_to_band_service_set_path(@set) }
    follow_redirect!
    assert_select "[data-role=flash-alert]"
  end

  test "an empty service is not sent" do
    @set.set_items.destroy_all
    login(@editor)
    assert_no_enqueued_emails { post send_to_band_service_set_path(@set) }
  end

  test "show page opens a confirmation modal listing the recipients, not a browser prompt" do
    login(@editor)
    get service_set_path(@set)
    assert_select "button[data-role=send-to-band][onclick*='send-to-band-modal']"
    assert_select "[data-turbo-confirm]", count: 0
    assert_select "dialog#send-to-band-modal" do
      assert_select "p", text: /2 band members/
      assert_select "[data-role=send-to-band-recipients] li", count: 2
      assert_select "[data-role=send-to-band-recipients]", text: /drums@example\.com.*keys@example\.com/m
      assert_select "form[action='#{send_to_band_service_set_path(@set)}'] [data-role=send-to-band-confirm]"
    end
  end

  test "no modal when there is no band" do
    @church.users.update_all(band_member: false)
    login(@editor)
    get service_set_path(@set)
    assert_select "dialog#send-to-band-modal", count: 0
    assert_select ".tooltip [data-role=send-to-band].btn-disabled"
  end

  test "signed-out users cannot send" do
    assert_no_enqueued_emails { post send_to_band_service_set_path(@set) }
    assert_redirected_to login_path
  end

  test "cross-church set is a 404" do
    other_set = @other.service_sets.create!(name: "Ajeno")
    login(@editor)
    assert_no_enqueued_emails { post send_to_band_service_set_path(other_set) }
    assert_response :not_found
  end
end

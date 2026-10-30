require "test_helper"

class ServiceSetsMailerTest < ActionMailer::TestCase
  setup do
    @church = Church.create!(name: "Central")
    @sender = User.create!(church: @church, email: "leader@example.com", password: "secret123", role: "editor")
    @player = User.create!(church: @church, email: "bass@example.com", password: "secret123", role: "editor",
                           band_member: true)
    @song  = @church.songs.create!(title: "Amazing Grace", song_key: "G",
                                   chordpro_source: "{title: Amazing Grace}\n{sov}\n[G]Amazing grace\n{eov}")
    @slide = @church.text_slides.create!(title: "Welcome", pages: [ { "body_markdown" => "Hi" } ], reusable: true)
    @set = @church.service_sets.create!(name: "Sunday AM", service_date: Date.new(2026, 11, 1))
    @set.set_items.create!(item_type: "song", song: @song, position: 0)
    @set.set_items.create!(item_type: "text_slide", text_slide: @slide, position: 1)
  end

  test "addresses one band member, replies to the sender, lists items in order with a link" do
    mail = ServiceSetsMailer.band(@set, @player, @sender, "en")

    assert_equal [ "bass@example.com" ], mail.to
    assert_equal [ "leader@example.com" ], mail.reply_to
    assert_equal "Central: Sunday AM", mail.subject

    text = mail.text_part.body.decoded
    assert_match(/1\. Amazing Grace \(key G\)\s+2\. Welcome \(slide\)/, text)
    assert_includes text, "Sunday, November 1, 2026"
    assert_match %r{https?://[^/\s]+/sets/#{@set.id}/preview}, text
    assert_includes mail.html_part.body.decoded, "Amazing Grace"
  end

  test "uses the recipient's own locale when set, else the sender's" do
    @player.update!(locale: "es")
    assert_includes ServiceSetsMailer.band(@set, @player, @sender, "en").text_part.body.decoded, "Fecha: 01/11/2026"

    @player.update!(locale: nil)
    assert_includes ServiceSetsMailer.band(@set, @player, @sender, "es").text_part.body.decoded, "diapositiva"
  end
end

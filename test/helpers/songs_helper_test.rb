require "test_helper"

class SongsHelperTest < ActionView::TestCase
  test "musician_segment anchors the chord to the first word and leaves the rest wrappable" do
    html = musician_segment("chord" => "E", "text" => "Vamos a cantar con la música")
    frag = Nokogiri::HTML.fragment(html)

    seg = frag.at_css(".musician-seg.has-chord")
    assert_equal "E", seg.at_css(".musician-chord[data-role=chord]").text
    assert_equal "Vamos", seg.at_css(".musician-text").text
    # The tail is outside the unbreakable anchor, so it can wrap on a narrow screen.
    assert_equal " a cantar con la música", frag.at_css(".musician-tail").text
    assert_nil frag.at_css(".musician-seg .musician-tail")
    refute_includes html, "&nbsp;a"
  end

  test "musician_segment keeps a whitespace-only tail so adjacent words stay apart" do
    frag = Nokogiri::HTML.fragment(musician_segment("chord" => "A", "text" => "Tu "))

    assert_equal "Tu", frag.at_css(".musician-text").text
    assert_equal " ", frag.at_css(".musician-tail").text
  end

  test "musician_segment keeps a chord-only segment as a non-empty anchor" do
    frag = Nokogiri::HTML.fragment(musician_segment("chord" => "A", "text" => ""))

    assert_equal "A", frag.at_css(".musician-chord").text
    assert_equal "\u00A0", frag.at_css(".musician-text").text
    assert_nil frag.at_css(".musician-tail")
  end

  test "musician_segment without a chord has no chord padding class and escapes text" do
    frag = Nokogiri::HTML.fragment(musician_segment("chord" => nil, "text" => "<b>hola</b> mundo"))

    assert_nil frag.at_css(".has-chord")
    assert_equal "<b>hola</b>", frag.at_css(".musician-text").text
    assert_equal " mundo", frag.at_css(".musician-tail").text
  end
end

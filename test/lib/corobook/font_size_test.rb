require "test_helper"

class Corobook::FontSizeTest < ActiveSupport::TestCase
  test "a size in pt is its share of a 540 pt-tall screen, like a PowerPoint slide" do
    assert_in_delta 10.0, Corobook::FontSize.to_percent(54), 0.001
    assert_in_delta 7.407, Corobook::FontSize.to_percent(40), 0.001
  end

  test "every offered size is inside the allowed range" do
    assert Corobook::FontSize::OPTIONS.all? { |pt| Corobook::FontSize::RANGE.cover?(pt) }
  end
end

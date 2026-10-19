require "application_system_test_case"

class SmokeTest < ApplicationSystemTestCase
  test "app boots and serves the health check" do
    visit rails_health_check_path

    assert_selector "body[style*='green']"
  end
end

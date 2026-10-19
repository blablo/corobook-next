require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Chrome's own sandbox cannot start inside sandboxed/containerized runners; the test
  # browser only ever loads this app's pages.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ] do |options|
    options.add_argument("--no-sandbox")
  end
end

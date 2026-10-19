require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Chrome's own sandbox cannot start inside sandboxed/containerized runners; the test
  # browser only ever loads this app's pages.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ] do |options|
    options.add_argument("--no-sandbox")
    # In CI the browser and chromedriver must be the same version; CHROME_BIN pins the binary
    # that setup-chrome installed so Selenium does not pick up a different pre-installed Chrome.
    if (chrome_bin = ENV["CHROME_BIN"]).present?
      options.binary = chrome_bin
    end
  end
end

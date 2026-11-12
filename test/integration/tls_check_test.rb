require "test_helper"

class TlsCheckTest < ActionDispatch::IntegrationTest
  setup do
    Church.create!(name: "Gracia", subdomain: "gracia")
    @prev_host = ENV["APP_HOST"]
    ENV["APP_HOST"] = "next.corobook.com"
  end

  teardown { ENV["APP_HOST"] = @prev_host }

  test "approves the base host and www" do
    check "next.corobook.com"
    assert_response :ok
    check "www.next.corobook.com"
    assert_response :ok
  end

  test "approves an existing church subdomain, case-insensitively" do
    check "Gracia.next.corobook.com"
    assert_response :ok
  end

  test "refuses unknown churches, deeper hosts, other domains and a missing domain" do
    [ "nobody.next.corobook.com", "a.gracia.next.corobook.com", "gracia.evil.com", "" ].each do |domain|
      check domain
      assert_response :not_found, "expected #{domain.inspect} to be refused"
    end
  end

  private

  def check(domain) = get(tls_check_path, params: { domain: domain })
end

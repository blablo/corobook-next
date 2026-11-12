# Caddy's on-demand TLS "ask" endpoint. Before issuing a certificate for a hostname, the edge
# Caddy calls GET /internal/tls-check?domain=<host>; a 200 lets it issue, anything else refuses.
# Only the base host, www, and hosts of churches that actually exist are approved, so nobody can
# make Caddy request certificates (and burn Let's Encrypt rate limits) for made-up names.
class TlsChecksController < ActionController::Base
  include Authentication
  skip_before_action :set_current_user

  def show
    domain = params[:domain].to_s.downcase
    base = app_base_host

    if domain == base || domain == "www.#{base}" || church_host?(domain)
      head :ok
    else
      head :not_found
    end
  end

  private

  def church_host?(domain)
    label = church_subdomain_label(domain)
    label.present? && Church.exists?(subdomain: label)
  end
end

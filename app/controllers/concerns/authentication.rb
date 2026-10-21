module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :set_current_user
    helper_method :current_user, :current_church, :signed_in?, :subdomain_church
  end

  private

  # The church addressed by the request host, if any (approach A: a login convenience only — it
  # pre-selects the church at sign-in and does NOT scope tenancy after login, which still comes
  # from the signed-in user's own church).
  #
  # Churches live UNDER a configured base host: <church>.<base>, e.g. gracia.corobook.duckdns.org
  # where the base is corobook.duckdns.org. We resolve the church label by stripping the known base
  # host from the request host — deterministic regardless of tld_length / domain depth, unlike
  # request.subdomain (which miscounts labels on multi-level hosts like *.duckdns.org). Memoized.
  def subdomain_church
    return @subdomain_church if defined?(@subdomain_church)

    label = church_subdomain_label
    @subdomain_church = label.present? ? Church.find_by(subdomain: label) : nil
  end

  # The church label in front of the base host, or nil when the request is the bare base host
  # (or www). Case-insensitive; only a single leading label is treated as the church.
  def church_subdomain_label
    host = request.host.to_s.downcase
    base = app_base_host
    return nil if host.blank? || base.blank?
    return nil if host == base || host == "www.#{base}"

    suffix = ".#{base}"
    return nil unless host.end_with?(suffix)

    label = host.delete_suffix(suffix)
    # Only a single leading label is a church subdomain (gracia.base → "gracia"); anything deeper
    # (a.b.base) is not a church host.
    return nil if label.blank? || label.include?(".") || label == "www"

    label
  end

  # The app's canonical base host (no church subdomain), from APP_HOST, else the mailer host, else
  # the request's own host as a last resort (dev/localhost).
  def app_base_host
    ENV["APP_HOST"].presence ||
      Rails.application.config.action_mailer.default_url_options&.dig(:host).presence ||
      request.host
  end

  # Current is reset by the Rails executor around each HTTP request, so setting it here is
  # request-local. It is NOT reset around Action Cable / Solid Queue — code on those paths must
  # take the church/session explicitly and never read Current (design §3.2.3).
  def set_current_user
    user = User.find_by(id: session[:user_id])
    if user
      Current.user = user
      Current.church = user.church
    end
  end

  def current_user = Current.user
  def current_church = Current.church
  def signed_in? = Current.user.present?

  def require_sign_in
    redirect_to login_path, alert: "Please sign in." unless signed_in?
  end

  def sign_in(user)
    reset_session
    session[:user_id] = user.id
    Current.user = user
    Current.church = user.church
  end

  def sign_out
    reset_session
    Current.user = nil
    Current.church = nil
  end
end

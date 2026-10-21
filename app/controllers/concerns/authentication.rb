module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :set_current_user
    helper_method :current_user, :current_church, :signed_in?, :subdomain_church
  end

  private

  # The church addressed by the request's subdomain, if any (approach A: a login convenience only —
  # it pre-selects the church at sign-in and does NOT scope tenancy after login, which still comes
  # from the signed-in user's own church). Ignores empty/`www` subdomains and anything unmatched.
  # Memoized per request.
  def subdomain_church
    return @subdomain_church if defined?(@subdomain_church)

    label = request.subdomain.to_s.split(".").first.to_s.downcase
    @subdomain_church =
      if label.blank? || label == "www"
        nil
      else
        Church.find_by(subdomain: label)
      end
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

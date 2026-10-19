module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :set_current_user
    helper_method :current_user, :current_church, :signed_in?
  end

  private

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

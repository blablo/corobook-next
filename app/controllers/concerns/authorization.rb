module Authorization
  extend ActiveSupport::Concern

  included do
    helper_method :can_edit? if respond_to?(:helper_method)
  end

  private

  # editor is the lower tier; admin satisfies both gates.
  def require_editor
    deny unless signed_in? && (Current.user.editor? || Current.user.admin?)
  end

  def require_admin
    deny unless signed_in? && Current.user.admin?
  end

  def deny
    if signed_in?
      redirect_to login_path, alert: "You are not allowed to do that."
    else
      redirect_to login_path, alert: "Please sign in."
    end
  end

  def can_edit? = signed_in?
end

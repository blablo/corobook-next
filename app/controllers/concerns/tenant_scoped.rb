module TenantScoped
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  end

  private

  # Every scoped query roots at the signed-in church's association, never Model.all.
  # association must be a has_many on Church, e.g. church_scope(:songs).
  def church_scope(association)
    Current.church.public_send(association)
  end

  # Loads a record only if it belongs to the current church; a cross-church id raises
  # RecordNotFound → 404 (design §3.2: do not reveal existence with a 403).
  def find_in_church(association, id)
    church_scope(association).find(id)
  end

  def render_not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end

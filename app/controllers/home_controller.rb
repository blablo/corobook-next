class HomeController < ApplicationController
  # The root is public: signed-out visitors see the marketing landing page; signed-in users get
  # their dashboard. So no blanket require_sign_in here — we branch on auth instead.
  def show
    if signed_in?
      render_dashboard
    else
      render "home/landing", layout: "public"
    end
  end

  private

  def render_dashboard
    @active_session = church_scope(:live_sessions).find_by(status: "active")
    @hero_set = HeroSet.for(Current.church)
    @recent_sets = church_scope(:service_sets)
      .order(Arel.sql("service_date DESC NULLS LAST, name ASC")).limit(5)
    @counts = {
      songs: church_scope(:songs).count,
      slides: church_scope(:text_slides).where(reusable: true).count,
      sets: church_scope(:service_sets).count
    }
    render "home/show", layout: "shell"
  end
end

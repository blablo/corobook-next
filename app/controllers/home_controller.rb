class HomeController < ApplicationController
  before_action :require_sign_in

  def show
    @active_session = church_scope(:live_sessions).find_by(status: "active")
    @hero_set = HeroSet.for(Current.church)
    @recent_sets = church_scope(:service_sets)
      .order(Arel.sql("service_date DESC NULLS LAST, name ASC")).limit(5)
    @counts = {
      songs: church_scope(:songs).count,
      slides: church_scope(:text_slides).where(reusable: true).count,
      sets: church_scope(:service_sets).count
    }
  end
end

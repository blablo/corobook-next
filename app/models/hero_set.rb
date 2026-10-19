# frozen_string_literal: true

# Picks the Set the home-page hero should feature (design §3): the nearest upcoming service by
# date, else the most recent, else nil for a church with no sets. Church-scoped via the passed
# church's association.
class HeroSet
  def self.for(church)
    upcoming = church.service_sets
                 .where("service_date >= ?", Date.current)
                 .order(:service_date).first
    upcoming || church.service_sets.order(Arel.sql("service_date DESC NULLS LAST")).first
  end
end

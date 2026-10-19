module ChurchChild
  extend ActiveSupport::Concern

  included do
    belongs_to :church
    validate :church_matches_parent
  end

  class_methods do
    # Declares a parent association whose church_id this record must match, e.g.
    #   church_parent :set        # a set_item's church must equal its set's church
    def church_parent(name)
      @church_parent = name
    end

    def church_parent_name = @church_parent
  end

  private

  def church_matches_parent
    name = self.class.church_parent_name
    return unless name

    parent = public_send(name)
    return if parent.nil? || parent.church_id.nil?

    if church_id != parent.church_id
      errors.add(:church_id, "must match #{name}'s church")
    end
  end
end

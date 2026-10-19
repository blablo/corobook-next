# Off-request church resolution (design §3.2.3). Action Cable and Solid Queue do NOT reset
# Current, so code on those paths must derive the church from an explicitly-passed object
# instead of reading Current.church. Every off-request caller goes through here, which fails
# loudly if someone passes nil rather than silently falling back to a leaked Current value.
module OffRequestTenant
  module_function

  # scoped is any record that responds to #church (e.g. a LiveSession, Song).
  def church_for(scoped)
    raise ArgumentError, "off-request tenant object is required" if scoped.nil?

    scoped.church
  end
end

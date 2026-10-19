class LiveSession < ApplicationRecord
  include ChurchChild
  church_parent :service_set

  belongs_to :service_set
  belongs_to :current_set_item, class_name: "SetItem", optional: true

  enum :status, { active: "active", ended: "ended" }, validate: true

  # Launch one run of a Set: seed position at its first item, issue follow tokens. The row is the
  # authoritative live state (design §6.1); Cable is only transport.
  def self.launch(service_set)
    first_item = service_set.set_items.order(:position).first
    create!(
      church: service_set.church,
      service_set: service_set,
      status: "active",
      current_set_item: first_item,
      current_section_index: 0,
      position_version: 0,
      projector_token: SecureRandom.urlsafe_base64(24),
      musician_token: SecureRandom.urlsafe_base64(24),
      started_at: Time.current
    )
  end

  def end!
    update!(status: "ended", projector_token: nil, musician_token: nil, ended_at: Time.current)
  end

  def current_item = current_set_item&.item
end

class Church < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :songs, dependent: :destroy
  has_many :text_slides, dependent: :destroy
  has_many :service_sets, dependent: :destroy
  has_many :live_sessions, dependent: :destroy
  has_many :usage_events, dependent: :destroy

  validates :name, presence: true

  # Members with the admin role.
  def admins
    users.where(role: "admin")
  end

  # True only when `user` is the church's sole admin — the last-admin lockout guard (D-U9).
  def only_admin?(user)
    return false unless user&.admin?

    admin_ids = admins.pluck(:id)
    admin_ids == [ user.id ]
  end
end

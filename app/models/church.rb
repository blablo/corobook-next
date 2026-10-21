class Church < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :songs, dependent: :destroy
  has_many :text_slides, dependent: :destroy
  has_many :service_sets, dependent: :destroy
  has_many :live_sessions, dependent: :destroy
  has_many :usage_events, dependent: :destroy

  validates :name, presence: true

  # Optional unique subdomain (e.g. "gracia" → gracia.example.com). When set it will later let a
  # church's members skip the church picker at login. Nil/blank = no subdomain (unset).
  # Rules: 3–63 chars, lowercase letters/digits/hyphens, not starting/ending with a hyphen, and
  # not a reserved host label.
  RESERVED_SUBDOMAINS = %w[www app admin api mail smtp ftp assets cdn static help support status
                           blog dev staging test localhost root].freeze
  SUBDOMAIN_FORMAT = /\A[a-z0-9]([a-z0-9-]{1,61}[a-z0-9])?\z/

  validates :subdomain,
            uniqueness: { case_sensitive: false },
            length: { in: 3..63 },
            format: { with: SUBDOMAIN_FORMAT,
                      message: "may contain only lowercase letters, numbers, and hyphens (not at the ends)" },
            exclusion: { in: RESERVED_SUBDOMAINS, message: "is reserved" },
            allow_blank: true

  # Normalize to a clean lowercase label before validation; blank becomes nil (unset).
  before_validation :normalize_subdomain

  def normalize_subdomain
    self.subdomain = subdomain.to_s.strip.downcase.presence
  end

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

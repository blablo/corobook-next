class Church < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :songs, dependent: :destroy
  has_many :text_slides, dependent: :destroy
  has_many :service_sets, dependent: :destroy
  has_many :live_sessions, dependent: :destroy
  has_many :usage_events, dependent: :destroy

  validates :name, presence: true

  # ── Projector settings (per-church projection look & behaviour) ──────────────
  CASE_OPTIONS        = %w[none upper title].freeze
  FONT_OPTIONS        = %w[sans serif condensed mono].freeze
  LINE_HEIGHT_OPTIONS = %w[tight normal relaxed].freeze
  VALIGN_OPTIONS      = %w[top center bottom].freeze
  PAGINATION_OPTIONS  = %w[by_section by_lines].freeze
  BG_TYPE_OPTIONS     = %w[solid gradient].freeze
  HEX_COLOR_FORMAT    = /\A#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\z/

  validates :projector_bg_color, :projector_text_color, :projector_bg_color2,
            format: { with: HEX_COLOR_FORMAT, message: "must be a hex color like #112233" }
  validates :projector_bg_type, inclusion: { in: BG_TYPE_OPTIONS }
  validates :projector_bg_gradient_angle,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 360 }
  validates :projector_lyric_case, :projector_title_case, inclusion: { in: CASE_OPTIONS }
  validates :projector_font, inclusion: { in: FONT_OPTIONS }
  validates :projector_line_height, inclusion: { in: LINE_HEIGHT_OPTIONS }
  validates :projector_valign, inclusion: { in: VALIGN_OPTIONS }
  validates :projector_pagination, inclusion: { in: PAGINATION_OPTIONS }
  validates :projector_lines_per_slide,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 20 }
  # Song lyric font size as % of screen height; nil = auto (fit to screen).
  validates :projector_font_size, numericality: { only_integer: true, in: 2..30 }, allow_nil: true

  # A value object bundling the projection settings, for CSS-variable + casing generation.
  def projector_settings
    Corobook::ProjectorSettings.new(self)
  end

  def paginate_by_lines? = projector_pagination == "by_lines"

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

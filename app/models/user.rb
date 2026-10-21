class User < ApplicationRecord
  has_secure_password

  belongs_to :church

  enum :role, { admin: "admin", editor: "editor" }, validate: true

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, uniqueness: { scope: :church_id, case_sensitive: false }
  # Enforce a minimum password length on set (has_secure_password only requires presence).
  # allow_nil lets an update that does not touch the password through unchanged.
  validates :password, length: { minimum: 8 }, allow_nil: true

  # ── Email confirmation (self-serve signup gate) ──────────────────────────────
  # The account is created at signup but cannot sign in until the emailed link is clicked.
  # The raw token lives only in memory on the instance that minted it; the column stores its
  # SHA-256 digest (same single-use pattern as Invitation).
  CONFIRMATION_EXPIRY = 2.days

  attr_reader :raw_confirmation_token

  def confirmed? = confirmed_at.present?

  # A user created WITHOUT going through the self-serve signup path is trusted and confirmed on
  # create: invited members (the invite proves email ownership), seeded/console/admin-made users.
  # The only unconfirmed path is self-serve signup, which mints a confirmation token first — so if
  # a token is present at create time, we leave the account unconfirmed for the email gate.
  before_validation :confirm_unless_pending_confirmation, on: :create

  def confirm_unless_pending_confirmation
    self.confirmed_at ||= Time.current if confirmation_token_digest.blank?
  end

  # Mint (or re-mint) a fresh confirmation token. Call before saving on signup and on resend.
  def regenerate_confirmation_token!
    @raw_confirmation_token = SecureRandom.urlsafe_base64(32)
    self.confirmation_token_digest = self.class.confirmation_digest(@raw_confirmation_token)
    self.confirmation_sent_at = Time.current
    @raw_confirmation_token
  end

  # Mark confirmed and clear the (now spent) token.
  def confirm!
    update!(confirmed_at: Time.current, confirmation_token_digest: nil)
  end

  def confirmation_expired?
    confirmation_sent_at.present? && confirmation_sent_at < CONFIRMATION_EXPIRY.ago
  end

  def self.confirmation_digest(raw)
    Digest::SHA256.hexdigest(raw.to_s)
  end

  # The user for a raw confirmation token when it is still usable (unconfirmed + unexpired); else nil.
  def self.find_by_confirmation_token(raw)
    return nil if raw.blank?

    user = find_by(confirmation_token_digest: confirmation_digest(raw))
    user if user && !user.confirmed? && !user.confirmation_expired?
  end
end

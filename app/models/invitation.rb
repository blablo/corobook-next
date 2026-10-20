require "digest"

class Invitation < ApplicationRecord
  belongs_to :church
  belongs_to :invited_by, class_name: "User"

  enum :role, { admin: "admin", editor: "editor" }, validate: true

  normalizes :email, with: ->(e) { e.to_s.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  EXPIRY = 14.days

  # The raw token is only ever held in memory on the instance that minted it; the column stores
  # its digest (Req 6.1). Readers resolve by hashing the path token.
  attr_reader :raw_token

  scope :pending, -> { where(accepted_at: nil) }

  def pending?    = accepted_at.nil?
  def expired?    = expires_at.present? && expires_at.past?
  def acceptable? = pending? && !expired?

  # Mint (or re-mint) a fresh single-use token + expiry. Call before save on create and on resend.
  def regenerate_token!
    @raw_token        = SecureRandom.urlsafe_base64(32) # ~192 bits of entropy, URL-safe
    self.token_digest = self.class.digest(@raw_token)
    self.expires_at   = EXPIRY.from_now
    @raw_token
  end

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw.to_s)
  end

  # Returns the invitation for a raw token only when it is still acceptable (pending + unexpired);
  # nil for unknown, expired, or already-accepted tokens.
  def self.find_acceptable_by_token(raw)
    return nil if raw.blank?

    invitation = find_by(token_digest: digest(raw))
    invitation if invitation&.acceptable?
  end
end

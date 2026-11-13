# Bearer token for the JSON import API (Api::V1). Acts as its user: same church, same role gate.
# Only the SHA-256 digest is stored; the raw token is shown once, at creation.
class ApiToken < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  # Returns [record, raw_token]. The raw value cannot be recovered later.
  def self.issue!(user:, name:)
    raw = "cbk_#{SecureRandom.urlsafe_base64(32)}"
    [ create!(user: user, name: name, token_digest: digest(raw)), raw ]
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw.to_s)

  def self.authenticate(raw)
    return nil if raw.blank?

    find_by(token_digest: digest(raw))
  end
end

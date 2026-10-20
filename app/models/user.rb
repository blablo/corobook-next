class User < ApplicationRecord
  has_secure_password

  belongs_to :church

  enum :role, { admin: "admin", editor: "editor" }, validate: true

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, uniqueness: { scope: :church_id, case_sensitive: false }
  # Enforce a minimum password length on set (has_secure_password only requires presence).
  # allow_nil lets an update that does not touch the password through unchanged.
  validates :password, length: { minimum: 8 }, allow_nil: true
end

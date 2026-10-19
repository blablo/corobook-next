class User < ApplicationRecord
  has_secure_password

  belongs_to :church

  enum :role, { admin: "admin", editor: "editor" }, validate: true

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, uniqueness: { scope: :church_id, case_sensitive: false }
end

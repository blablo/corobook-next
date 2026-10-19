class Church < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :songs, dependent: :destroy

  validates :name, presence: true
end

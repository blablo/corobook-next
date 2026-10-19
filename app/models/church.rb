class Church < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :songs, dependent: :destroy
  has_many :text_slides, dependent: :destroy
  has_many :service_sets, dependent: :destroy
  has_many :live_sessions, dependent: :destroy
  has_many :usage_events, dependent: :destroy

  validates :name, presence: true
end

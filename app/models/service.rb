class Service < ApplicationRecord
  belongs_to :fixed_staff, class_name: 'Staff', optional: true
  has_many :staff_services, primary_key: :name, foreign_key: :service

  validates :name, presence: true, uniqueness: true
  validates :display_name, presence: true
  validates :max_concurrent, numericality: { greater_than_or_equal_to: 0 }
  validates :min_duration, :max_duration, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }

  def bookable?
    active && max_concurrent > 0
  end
end

class StaffService < ApplicationRecord
  belongs_to :staff

  validates :service, presence: true
  validates :staff_id, uniqueness: { scope: :service }
end

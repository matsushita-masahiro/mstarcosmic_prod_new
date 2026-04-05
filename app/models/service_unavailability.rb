class ServiceUnavailability < ApplicationRecord
  validates :service, :date, :start_time, :end_time, presence: true

  scope :for_date, ->(date) { where(date: date) }
  scope :for_dates, ->(dates) { where(date: dates) }
  scope :for_service, ->(service) { where(service: service) }
  scope :overlapping, ->(start_t, end_t) {
    where('start_time < ? AND end_time > ?', end_t, start_t)
  }
end

class Reservation < ApplicationRecord
  belongs_to :user
  belongs_to :staff, optional: true

  validates :service, :date, :start_time, :end_time, :duration, presence: true
  validates :status, inclusion: { in: [0, 1] }
  validate :end_after_start

  scope :confirmed, -> { where(status: 0) }
  scope :for_date, ->(date) { where(date: date) }
  scope :for_dates, ->(dates) { where(date: dates) }
  scope :overlapping, ->(start_t, end_t) {
    where('start_time < ? AND end_time > ?', end_t, start_t)
  }

  def confirmed?
    status == 0
  end

  def cancelled?
    status == 1
  end

  private

  def end_after_start
    return unless start_time && end_time
    errors.add(:end_time, 'は開始時刻より後にしてください') if end_time <= start_time
  end
end

class StaffSchedule < ApplicationRecord
  belongs_to :staff

  validates :date, :start_time, :end_time, presence: true
  validates :staff_id, uniqueness: { scope: [:date, :start_time] }
  validate :end_after_start

  scope :for_date, ->(date) { where(date: date) }
  scope :for_dates, ->(dates) { where(date: dates) }
  scope :covering, ->(time) { where('start_time <= ? AND end_time > ?', time, time) }

  private

  def end_after_start
    return unless start_time && end_time
    errors.add(:end_time, 'は開始時刻より後にしてください') if end_time <= start_time
  end
end

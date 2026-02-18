class NewSchedule < ApplicationRecord
    belongs_to :new_staff, class_name: 'NewStaff', foreign_key: :new_staff_id
  
    validates :date, :time_slot, presence: true
    validates :working, inclusion: { in: [true, false] }
    validates :time_slot, inclusion: { in: 0..24 } # 10:00-22:00を30分単位で0-24の値で管理
  
    scope :working, -> { where(working: true) }
    scope :for_date, ->(date) { where(date: date) }
    scope :for_time_slot, ->(time_slot) { where(time_slot: time_slot) }
  
    def self.time_slot_to_time(slot)
      hour = 10 + (slot / 2)
      minute = (slot % 2) * 30
      "#{hour.to_s.rjust(2, '0')}:#{minute.to_s.rjust(2, '0')}"
    end
  
    def self.time_to_time_slot(hour, minute)
      return nil if hour < 10 || hour > 22
      (hour - 10) * 2 + (minute >= 30 ? 1 : 0)
    end

  end
  
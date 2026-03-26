class NewReserve < ApplicationRecord
    belongs_to :user, optional: true
    belongs_to :new_staff, class_name: 'NewStaff', foreign_key: :new_staff_id
  
    enum :customer_gender, { customer_male: 0, customer_female: 1, customer_other: 2 }
    enum :duration, { thirty_minutes: 1, sixty_minutes: 2 }
  
    validates :date, :start_time_slot, :duration, presence: true
    validates :start_time_slot, inclusion: { in: 0..24 }
    validate :date_cannot_be_in_the_past
  
    # user未登録の場合は顧客情報が必須
    validates :customer_name, :customer_gender, :customer_tel, presence: true, if: -> { user.nil? }
  
    scope :for_date, ->(date) { where(date: date) }
    scope :for_time_slot, ->(time_slot) { where(start_time_slot: time_slot) }
    scope :overlapping, ->(start_slot, duration) {
      where(
        "(start_time_slot <= ? AND start_time_slot + duration - 1 >= ?) OR " \
        "(start_time_slot <= ? AND start_time_slot + duration - 1 >= ?)",
        start_slot, start_slot,
        start_slot + duration - 1, start_slot + duration - 1
      )
    }
  
    def end_time_slot
      duration_value = case duration
                      when 'thirty_minutes'
                        1
                      when 'sixty_minutes'
                        2
                      else
                        duration.to_i
                      end
      start_time_slot + duration_value - 1
    end
  
    def time_slots
      (start_time_slot..end_time_slot).to_a
    end
  
    def customer_display_name
      user&.name || customer_name
    end
  
    def customer_display_gender
      user&.gender || customer_gender
    end
  
    def customer_display_tel
      user&.tel || customer_tel
    end
  
    private
  
    def date_cannot_be_in_the_past
      if date.present? && date < Date.tomorrow
        errors.add(:date, "は明日以降の日付を選択してください")
      end
    end
  end
  
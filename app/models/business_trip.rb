class BusinessTrip < ApplicationRecord
    belongs_to :new_machine, class_name: 'NewMachine', foreign_key: :new_machine_id

    validates :date, :time_slot, presence: true
    validates :time_slot, inclusion: { in: 0..24 }
  
    scope :for_date, ->(date) { where(date: date) }
    scope :for_time_slot, ->(time_slot) { where(time_slot: time_slot) }
  end
  
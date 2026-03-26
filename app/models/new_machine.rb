class NewMachine < ApplicationRecord
    validates :name, :total_count, presence: true
    validates :total_count, numericality: { greater_than: 0 }
  
    has_many :business_trips, foreign_key: :new_machine_id, dependent: :destroy
  
    def available_count_at(date, time_slot)
      business_trip_count = business_trips.where(date: date, time_slot: time_slot).count
      total_count - business_trip_count
    end
  end
  
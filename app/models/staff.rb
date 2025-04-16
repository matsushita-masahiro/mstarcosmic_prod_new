class Staff < ApplicationRecord
    # belongs_to :user
    has_many :reserves
    has_many :staff_machine_relations
    accepts_nested_attributes_for :staff_machine_relations
    has_many :schedules
    
      validates :name, presence: true
      validates :name_kanji, presence: true
      
    def staff_machines
      self.staff_machine_relations.pluck(:machine).join(',')
    end

      
end

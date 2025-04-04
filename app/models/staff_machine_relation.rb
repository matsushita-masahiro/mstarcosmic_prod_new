class StaffMachineRelation < ApplicationRecord
    belongs_to :staff
    
    scope :esute_staff_id, -> { find_by(machine: "e").staff_id }
    scope :body_staff_id, -> { find_by(machine: "b").staff_id }

    
end

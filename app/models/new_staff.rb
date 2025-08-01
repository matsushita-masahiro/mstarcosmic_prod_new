class NewStaff < ApplicationRecord
    enum :staff_type, { admin: 0, staff_x: 1, staff_z: 2 }
  
    validates :name, :staff_type, presence: true
    validates :active, inclusion: { in: [true, false] }
  
    has_many :new_schedules, foreign_key: :new_staff_id, dependent: :destroy
    has_many :new_reserves, foreign_key: :new_staff_id, dependent: :destroy
  
    scope :active, -> { where(active: true) }
    scope :admin_staff, -> { where(staff_type: :admin) }
    scope :staff_x, -> { where(staff_type: :staff_x) }
    scope :staff_z, -> { where(staff_type: :staff_z) }
  
    def staff_type_i18n
      case staff_type
      when 'admin'
        '管理者'
      when 'staff_x'
        'スタッフX'
      when 'staff_z'
        'スタッフZ'
      else
        staff_type
      end
    end
  end
  
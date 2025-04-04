class Schedule < ApplicationRecord
  belongs_to :staff
  attr_accessor :calender_start_day
  
  
  def self.adjust_record
      logger.debug("====================== schedule adjust_record = #{self.last.id}")
      self.last.destroy
      puts "adjust_record puts"
  end  
  
  scope :attendance_staffs_array, -> (date, space) { where(schedule_date: date, schedule_space: space).pluch(:staff_id) }
  scope :h_attendance_staffs_array, -> (date, space) { where(schedule_date: date, schedule_space: space, staff_id: StaffMachineRelation.where(machine: "h").pluck(:staff_id)).pluck(:staff_id) }
  scope :w_attendance_staffs_array, -> (date, space) { where(schedule_date: date, schedule_space: space, staff_id: StaffMachineRelation.where(machine: "w").pluck(:staff_id)).pluck(:staff_id) }
  scope :wh_attendance_staffs_array, -> (date, space) { where(schedule_date: date, schedule_space: space, staff_id: StaffMachineRelation.where(machine: ["w","h"]).pluck(:staff_id)).pluck(:staff_id) }

  
end

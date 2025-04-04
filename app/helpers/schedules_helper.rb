module SchedulesHelper
    
    def attendance_staff(date, space)
        logger.debug("~~~~~~~~~~~~~~~~~~~~~ attendance_staff date = #{date}  space = #{space}")
        if Schedule.find_by(schedule_date: date, schedule_space: space)
            attendance_staffs = []
            attendance_staffs_array = Schedule.where(schedule_date: date, schedule_space: space).order(:staff_id).pluck(:staff_id)
          logger.debug("~~~~~~~~~~~~~~~~~~~~~ attendance_staff schedule 有 attendance_staffs_array = #{attendance_staffs_array}")
            attendance_staffs_array.each do |staff_id|
                attendance_staffs << Staff.find(staff_id).name_kanji
            end
            
        else
            attendance_staffs = ["=="]
        end
        
        return attendance_staffs
    end
end

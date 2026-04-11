class Schedule < ApplicationRecord
  belongs_to :staff
  attr_accessor :calender_start_day, :skip_staff_schedule_sync

  # 旧Schedule変更時に新StaffScheduleへ自動同期
  after_commit :sync_to_staff_schedule, on: [:create, :update], unless: :skip_staff_schedule_sync
  after_commit :sync_to_staff_schedule_on_destroy, on: :destroy, unless: :skip_staff_schedule_sync

  def self.adjust_record
      logger.debug("====================== schedule adjust_record = #{self.last.id}")
      self.last.destroy
      puts "adjust_record puts"
  end  
  
  scope :attendance_staffs_array, -> (date, space) { where(schedule_date: date, schedule_space: space).pluch(:staff_id) }
  scope :h_attendance_staffs_array, -> (date, space) { where(schedule_date: date, schedule_space: space, staff_id: StaffMachineRelation.where(machine: "h").pluck(:staff_id)).pluck(:staff_id) }
  scope :w_attendance_staffs_array, -> (date, space) { where(schedule_date: date, schedule_space: space, staff_id: StaffMachineRelation.where(machine: "w").pluck(:staff_id)).pluck(:staff_id) }
  scope :wh_attendance_staffs_array, -> (date, space) { where(schedule_date: date, schedule_space: space, staff_id: StaffMachineRelation.where(machine: ["w","h"]).pluck(:staff_id)).pluck(:staff_id) }

  private

  # 同じスタッフ・日付の全スロットを再集約してStaffScheduleを再作成
  def rebuild_staff_schedule(sid, date)
    StaffSchedule.where(staff_id: sid, date: date).delete_all

    spaces = Schedule.where(staff_id: sid, schedule_date: date)
                     .order(:schedule_space)
                     .pluck(:schedule_space)
    return if spaces.empty?

    # 連続スロットをまとめる
    ranges = []
    cs = spaces.first
    ce = spaces.first
    spaces[1..].each do |sp|
      if (sp - ce - 0.5).abs < 0.01
        ce = sp
      else
        ranges << [cs, ce + 0.5]
        cs = sp
        ce = sp
      end
    end
    ranges << [cs, ce + 0.5]

    ranges.each do |s, e|
      sh = s.to_i; sm = (s % 1 == 0.5) ? 30 : 0
      eh = e.to_i; em = (e % 1 == 0.5) ? 30 : 0
      StaffSchedule.create!(
        staff_id: sid, date: date,
        start_time: Time.zone.parse('2000-01-01').change(hour: sh, min: sm),
        end_time:   Time.zone.parse('2000-01-01').change(hour: eh, min: em)
      )
    end
  end

  def sync_to_staff_schedule
    rebuild_staff_schedule(staff_id, schedule_date)
  end

  def sync_to_staff_schedule_on_destroy
    rebuild_staff_schedule(staff_id_before_last_save || staff_id, schedule_date)
  end
end

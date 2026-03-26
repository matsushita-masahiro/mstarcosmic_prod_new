class NewStaffSchedulesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin
  
  def index
    @start_date = params[:date]&.to_date || Date.current
    @dates = (0..6).map { |i| @start_date + i.days }
    @time_slots = generate_time_slots
    @staffs = NewStaff.where(active: true).order(:name)
    @selected_staff = params[:staff_id].present? ? NewStaff.find(params[:staff_id]) : @staffs.first
    
    if @selected_staff
      @weekly_schedules = get_weekly_schedules(@selected_staff, @dates)
    end
  end
  
  def show
    @staff = NewStaff.find(params[:id])
    @start_date = params[:date]&.to_date || Date.current
    @dates = (0..6).map { |i| @start_date + i.days }
    @time_slots = generate_time_slots
    @weekly_schedules = get_weekly_schedules(@staff, @dates)
  end
  
  def bulk_update
    staff_id = params[:staff_id]
    schedules_data = params[:schedules] || {}
    
    begin
      ActiveRecord::Base.transaction do
        schedules_data.each do |date_str, time_slots|
          date = Date.parse(date_str)
          
          time_slots.each do |time_slot, working|
            schedule = NewSchedule.find_or_initialize_by(
              new_staff_id: staff_id,
              date: date,
              time_slot: time_slot.to_i
            )
            
            schedule.working = working == '1'
            schedule.save!
          end
        end
      end
      
      redirect_to new_staff_schedules_path(staff_id: staff_id, date: params[:date]), 
                  notice: 'スケジュールを更新しました。'
    rescue => e
      Rails.logger.error "Schedule update error: #{e.message}"
      redirect_to new_staff_schedules_path(staff_id: staff_id, date: params[:date]), 
                  alert: 'スケジュールの更新に失敗しました。'
    end
  end
  
  private
  
  def ensure_admin
    unless current_user&.admin?
      redirect_to root_path, alert: '管理者権限が必要です。'
    end
  end
  
  def generate_time_slots
    slots = []
    (0..24).each do |slot|
      hour = 10 + (slot / 2)
      minute = (slot % 2) * 30
      break if hour > 22
      
      time_str = "#{hour.to_s.rjust(2, '0')}:#{minute.to_s.rjust(2, '0')}"
      slots << { slot: slot, time: time_str }
    end
    slots
  end
  
  def get_weekly_schedules(staff, dates)
    weekly_schedules = {}
    
    dates.each do |date|
      weekly_schedules[date] = {}
      @time_slots.each do |time_data|
        slot = time_data[:slot]
        
        schedule = NewSchedule.find_by(
          new_staff_id: staff.id,
          date: date,
          time_slot: slot
        )
        
        weekly_schedules[date][slot] = schedule&.working || false
      end
    end
    
    weekly_schedules
  end
end

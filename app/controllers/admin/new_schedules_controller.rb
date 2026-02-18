class Admin::NewSchedulesController < ApplicationController

    before_action :authenticate_admin!
  
  def index
    @date = params[:date]&.to_date || Date.current
    @staffs = NewStaff.active.includes(:schedules)
    @time_slots = generate_time_slots
    @schedules = NewSchedule.includes(:staff).where(date: @date)
  end

  def create
    @schedule = NewSchedule.new(schedule_params)
    
    if @schedule.save
      render json: { status: 'success', message: 'スケジュールを更新しました' }
    else
      render json: { status: 'error', errors: @schedule.errors.full_messages }
    end
  end

  def update
    @schedule = NewSchedule.find(params[:id])
    
    if @schedule.update(schedule_params)
      render json: { status: 'success', message: 'スケジュールを更新しました' }
    else
      render json: { status: 'error', errors: @schedule.errors.full_messages }
    end
  end

  def destroy
    @schedule = NewSchedule.find(params[:id])
    @schedule.destroy
    render json: { status: 'success', message: 'スケジュールを削除しました' }
  end

  private


  def schedule_params
    params.require(:schedule).permit(:staff_id, :date, :time_slot, :working)
  end

  def generate_time_slots
    slots = []
    (0..23).each do |slot|
      hour = 10 + (slot / 2)
      minute = (slot % 2) * 30
      break if hour > 21 || (hour == 21 && minute > 30)
      
      time_str = "#{hour.to_s.rjust(2, '0')}:#{minute.to_s.rjust(2, '0')}"
      slots << { slot: slot, time: time_str }
    end
    slots
  end
end

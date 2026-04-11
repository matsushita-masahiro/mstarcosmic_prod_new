class NewServiceUnavailabilitiesController < ApplicationController
  layout 'main/main'
  before_action :authenticate_user!
  before_action :ensure_admin
  before_action :set_dates

  def index
    @service = 'holistic'
    @staff_id = (params[:staff_id] || 1).to_i
    @time_slots = AvailabilityService.time_slots
    @weekly = {}
    @dates.each do |date|
      @weekly[date] = {}
      @time_slots.each do |slot|
        @weekly[date][slot] = ServiceUnavailability.where(service: @service, date: date, staff_id: @staff_id)
                                                    .where('start_time <= ? AND end_time > ?',
                                                           slot, slot).exists?
      end
    end
  end

  def create
    service = params[:service] || 'holistic'
    staff_id = (params[:staff_id] || 1).to_i
    ServiceUnavailability.where(service: service, date: @dates, staff_id: staff_id).destroy_all

    slots_by_date = {}
    (params[:slots] || {}).each do |key, _|
      date_str, time = key.split('_', 2)
      date = Date.parse(date_str)
      slots_by_date[date] ||= []
      slots_by_date[date] << time
    end

    slots_by_date.each do |date, times|
      times.sort!
      ranges = consolidate_times(times)
      ranges.each do |r|
        ServiceUnavailability.create!(service: service, date: date,
                                      start_time: r[:start], end_time: r[:end],
                                      reason: 'business_trip', staff_id: staff_id)
      end
    end

    # 旧machine_schedulesにも同期
    sync_to_old_machine_schedules(service, @dates)

    redirect_to new_service_unavailabilities_path(start_date: @start_date, staff_id: staff_id),
                notice: '出張スケジュールを保存しました'
  end

  def destroy
    ServiceUnavailability.find(params[:id]).destroy
    redirect_back fallback_location: new_service_unavailabilities_path, notice: '削除しました'
  end

  private

  def ensure_admin
    redirect_to root_path, alert: '管理者権限が必要です' unless current_user.user_type == '1'
  end

  def set_dates
    @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current
    @start_date = Date.current if @start_date < Date.current
    @dates = (0..6).map { |i| @start_date + i.days }
  end

  def consolidate_times(times)
    return [] if times.empty?
    ranges = []
    start_t = times.first
    prev_t = times.first
    times.each_with_index do |t, i|
      next if i == 0
      prev_min = time_to_min(prev_t)
      curr_min = time_to_min(t)
      if curr_min - prev_min == 30
        prev_t = t
      else
        ranges << { start: start_t, end: add_30min(prev_t) }
        start_t = t
        prev_t = t
      end
    end
    ranges << { start: start_t, end: add_30min(prev_t) }
    ranges
  end

  def time_to_min(t)
    h, m = t.split(':').map(&:to_i)
    h * 60 + m
  end

  def add_30min(t)
    m = time_to_min(t) + 30
    format('%02d:%02d', m / 60, m % 60)
  end

  def sync_to_old_machine_schedules(service, dates)
    machine_code = service == 'holistic' ? 'h' : 'w'
    MachineSchedule.where(machine: machine_code, machine_schedule_date: dates).delete_all
    ServiceUnavailability.where(service: service, date: dates).each do |su|
      h = su.start_time.hour; m = su.start_time.min
      eh = su.end_time.hour; em = su.end_time.min
      space = h + (m >= 30 ? 0.5 : 0.0)
      end_space = eh + (em >= 30 ? 0.5 : 0.0)
      while space < end_space
        MachineSchedule.create!(machine: machine_code, machine_schedule_date: su.date, machine_schedule_space: space)
        space += 0.5
      end
    end
  end
end

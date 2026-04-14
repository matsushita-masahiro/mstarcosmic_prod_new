class NewStaffSchedulesController < ApplicationController
  layout 'main/main'
  before_action :authenticate_user!
  before_action :ensure_admin
  before_action :set_dates

  def index
    @staffs = Staff.where(active_flag: true, dismiss_flag: false).where.not(id: 0).order(:id)
    @selected_staff = params[:staff_id].present? ? Staff.find(params[:staff_id]) : @staffs.first
    @time_slots = AvailabilityService.time_slots
    @weekly = {}
    @dates.each do |date|
      @weekly[date] = {}
      @time_slots.each do |slot|
        h, m = slot.split(':').map(&:to_i)
        t = Time.zone.parse('2000-01-01').change(hour: h, min: m)
        @weekly[date][slot] = StaffSchedule.where(staff_id: @selected_staff.id, date: date)
                                           .where('start_time <= ? AND end_time > ?',
                                                  t, t).exists?
      end
    end
  end

  def create
    staff_id = params[:staff_id].to_i
    # 週の全スケジュールを削除して再作成
    StaffSchedule.where(staff_id: staff_id, date: @dates).destroy_all

    # チェックされた枠を収集
    slots_by_date = {}
    (params[:slots] || {}).each do |key, _|
      date_str, time = key.split('_', 2)
      date = Date.parse(date_str)
      slots_by_date[date] ||= []
      slots_by_date[date] << time
    end

    # 連続スロットを範囲に集約して保存
    slots_by_date.each do |date, times|
      times.sort!
      ranges = consolidate_times(times)
      ranges.each do |r|
        StaffSchedule.create!(staff_id: staff_id, date: date, start_time: r[:start], end_time: r[:end])
      end
    end

    # 旧schedulesにも同期
    sync_to_old_schedules(staff_id, @dates)

    redirect_to new_staff_schedules_path(staff_id: staff_id, start_date: @start_date),
                notice: 'スケジュールを保存しました'
  end

  private

  def ensure_admin
    unless current_user.user_type.in?(%w[1 10])
      redirect_to root_path, alert: '権限がありません'
    end
  end

  def set_dates
    @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current + 1.day
    @start_date = Date.current + 1.day if @start_date <= Date.current
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

  def sync_to_old_schedules(staff_id, dates)
    Schedule.where(staff_id: staff_id, schedule_date: dates).delete_all
    StaffSchedule.where(staff_id: staff_id, date: dates).each do |ss|
      h = ss.start_time.hour; m = ss.start_time.min
      eh = ss.end_time.hour; em = ss.end_time.min
      space = h + (m >= 30 ? 0.5 : 0.0)
      end_space = eh + (em >= 30 ? 0.5 : 0.0)
      while space < end_space
        # 新→旧同期時はコールバックをスキップ（無限ループ防止）
        s = Schedule.new(staff_id: staff_id, schedule_date: ss.date, schedule_space: space)
        s.skip_staff_schedule_sync = true
        s.save!
        space += 0.5
      end
    end
  end
end

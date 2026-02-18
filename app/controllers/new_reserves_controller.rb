class NewReservesController < ApplicationController
  before_action :set_new_reserve, only: [:show, :destroy]
  before_action :authenticate_user!, only: [:index, :show]

  def index
    @new_reserves = current_user.new_reserves.includes(:new_staff).order(date: :desc, start_time_slot: :asc)
  end

  def show
  end

  def new
    @date = params[:date]&.to_date || Date.tomorrow
    @time_slot = params[:time_slot]&.to_i || 0

    if @date < Date.tomorrow
      redirect_to calendar_path, alert: '過去の日付は予約できません。'
      return
    end

    availability = calculate_slot_availability(@date, @time_slot)

    if availability[:status] == 'unavailable'
      redirect_to calendar_path(date: @date), alert: 'この時間帯は予約できません。'
      return
    end

    @new_reserve = NewReserve.new(date: @date, start_time_slot: @time_slot)
    @available_staff = get_available_staff(@date, @time_slot)
    @time_display = NewSchedule.time_slot_to_time(@time_slot)
  end

  def confirm
    Rails.logger.info "Confirm params: #{new_reserve_params.inspect}"
    @new_reserve = NewReserve.new(new_reserve_params)
    @new_reserve.user = current_user if user_signed_in?
    Rails.logger.info "User signed in: #{user_signed_in?}"
    Rails.logger.info "New reserve valid: #{@new_reserve.valid?}"
    Rails.logger.info "New reserve errors: #{@new_reserve.errors.full_messages}" unless @new_reserve.valid?

    if @new_reserve.date < Date.tomorrow
      redirect_to calendar_path, alert: '過去の日付は予約できません。'
      return
    end

    if @new_reserve.date == Date.tomorrow && Time.current.hour >= 15
      redirect_to calendar_path, alert: '翌日の予約は前日の15時までです。'
      return
    end

    unless @new_reserve.valid?
      @available_staff = get_available_staff(@new_reserve.date, @new_reserve.start_time_slot)
      @time_display = NewSchedule.time_slot_to_time(@new_reserve.start_time_slot)
      @date = @new_reserve.date
      @time_slot = @new_reserve.start_time_slot
      render :new and return
    end

    duration_value = @new_reserve.duration == "thirty_minutes" ? 1 : 2
    unless duration_value == 1 || can_reserve_sixty_minutes?(@new_reserve.date, @new_reserve.start_time_slot, @new_reserve.new_staff_id)
      redirect_to calendar_path(date: @new_reserve.date), alert: 'この枠は60分の予約ができません。'
      return
    end

    availability = calculate_slot_availability(@new_reserve.date, @new_reserve.start_time_slot, duration_value)

    if availability[:status] == 'unavailable'
      redirect_to calendar_path(date: @new_reserve.date), alert: 'この時間帯は既に予約が埋まっています。'
      return
    end

    @staff = NewStaff.find(@new_reserve.new_staff_id)
    @time_display = NewSchedule.time_slot_to_time(@new_reserve.start_time_slot)
  end

  def create
    @new_reserve = NewReserve.new(new_reserve_params)
    @new_reserve.user = current_user if user_signed_in?

    if @new_reserve.date < Date.tomorrow
      redirect_to calendar_path, alert: '過去の日付は予約できません。'
      return
    end

    if @new_reserve.date == Date.tomorrow && Time.current.hour >= 15
      redirect_to calendar_path, alert: '翌日の予約は前日の15時までです。'
      return
    end

    duration_value = @new_reserve.duration == "thirty_minutes" ? 1 : 2

    unless staff_available?(@new_reserve.new_staff_id, @new_reserve.date, @new_reserve.start_time_slot, duration_value)
      redirect_to calendar_path(date: @new_reserve.date), alert: 'スタッフが既に予約されています。'
      return
    end

    availability = calculate_slot_availability(@new_reserve.date, @new_reserve.start_time_slot, duration_value)

    if availability[:status] == 'unavailable'
      redirect_to calendar_path(date: @new_reserve.date), alert: '予約が埋まっています。'
      return
    end

    if @new_reserve.save
      redirect_to calendar_path(date: @new_reserve.date), notice: '予約が完了しました。'
    else
      @available_staff = get_available_staff(@new_reserve.date, @new_reserve.start_time_slot)
      @time_display = NewSchedule.time_slot_to_time(@new_reserve.start_time_slot)
      @date = @new_reserve.date
      @time_slot = @new_reserve.start_time_slot
      render :new
    end
  end

  def destroy
    if @new_reserve.user == current_user || (current_user&.admin?)
      @new_reserve.destroy
      redirect_to new_reserves_path, notice: '予約をキャンセルしました。'
    else
      redirect_to new_reserves_path, alert: '予約をキャンセルする権限がありません。'
    end
  end

  private

  def set_new_reserve
    @new_reserve = NewReserve.find(params[:id])
  end

  def new_reserve_params
    params.require(:new_reserve).permit(
      :date, :start_time_slot, :duration, :new_staff_id, :notes,
      :customer_name, :customer_gender, :customer_tel
    )
  end

  def get_available_staff(date, time_slot)
    working_staff = NewStaff.joins(:new_schedules)
      .where(new_schedules: { date: date, time_slot: time_slot, working: true })
      .where(active: true)

    reserved_staff_ids = NewReserve.where(date: date)
      .where('(start_time_slot <= ? AND start_time_slot + duration - 1 >= ?)', time_slot, time_slot)
      .pluck(:new_staff_id)

    working_staff.where.not(id: reserved_staff_ids)
  end

  def calculate_slot_availability(date, time_slot, duration = 1)
    machine = NewMachine.find_by(name: 'holistic')

    (0...duration).each do |offset|
      slot = time_slot + offset
      return { status: 'unavailable' } if machine.available_count_at(date, slot) <= 0
    end

    available_staff = get_available_staff(date, time_slot)
    count = available_staff.count

    if count >= 2
      { status: 'excellent', available_staff: count }
    elsif count == 1
      { status: 'good', available_staff: count }
    else
      { status: 'unavailable', available_staff: 0 }
    end
  end

  def staff_available?(staff_id, date, start_slot, duration)
    NewReserve.where(new_staff_id: staff_id, date: date)
      .where('(start_time_slot <= ? AND start_time_slot + duration - 1 >= ?)', start_slot, start_slot)
      .or(
        NewReserve.where(new_staff_id: staff_id, date: date)
        .where('(start_time_slot <= ? AND start_time_slot + duration - 1 >= ?)', start_slot + duration - 1, start_slot + duration - 1)
      )
      .none?
  end

  def can_reserve_sixty_minutes?(date, start_time_slot, staff_id)
    return false if start_time_slot + 1 > 24
    s1 = NewSchedule.exists?(new_staff_id: staff_id, date: date, time_slot: start_time_slot, working: true)
    s2 = NewSchedule.exists?(new_staff_id: staff_id, date: date, time_slot: start_time_slot + 1, working: true)
    return false unless s1 && s2

    machine = NewMachine.find_by(name: 'holistic')
    return false unless machine

    return false if machine.available_count_at(date, start_time_slot) == 0
    return false if machine.available_count_at(date, start_time_slot + 1) == 0

    staff_available?(staff_id, date, start_time_slot, 2)
  end
end

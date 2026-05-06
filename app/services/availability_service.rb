class AvailabilityService
  SLOT_MINUTES  = 30
  SLOTS_PER_DAY = 24
  CUTOFF_HOUR   = 15

  def self.time_slots
    @time_slots ||= SLOTS_PER_DAY.times.map do |i|
      format('%02d:%02d', 10 + i / 2, (i % 2) * 30)
    end.freeze
  end

  # サービスのmin_durationを考慮した表示用スロット
  def self.time_slots_for_service(service)
    last_start_hour = 22 * 60 - service.min_duration # 分単位
    time_slots.select do |t|
      h, m = t.split(':').map(&:to_i)
      (h * 60 + m) <= last_start_hour
    end
  end

  # @param service_name [String] 'holistic', 'seitai', 'shinkyu'
  # @param start_date [Date]
  # @param num_days [Integer]
  # @param user_signed_in [Boolean]
  def initialize(service_name, start_date, num_days: 7, user_signed_in: false)
    @service_name   = service_name
    @start_date     = start_date
    @num_days       = num_days
    @user_signed_in = user_signed_in
    @dates          = (0...num_days).map { |i| start_date + i.days }
  end

  # 週間空き状況
  # => { Date => { "10:00" => Integer(-1|0|1|2), ... }, ... }
  def calculate
    load_data
    result = {}
    @dates.each do |date|
      result[date] = {}
      self.class.time_slots.each do |slot|
        result[date][slot] = calc_slot(date, slot)
      end
    end
    result
  end

  # 管理者用: 週間予約一覧
  # => { Date => { "10:00" => [Reservation, ...], ... }, ... }
  def weekly_reservations
    load_data
    result = {}
    @dates.each do |date|
      result[date] = {}
      self.class.time_slots.each do |slot|
        s, e = slot_range(slot)
        result[date][slot] = (@res_idx[date] || []).select { |r| r.start_time < e && r.end_time > s }
      end
    end
    result
  end

  # 指定枠の空きスタッフ一覧（duration分の連続空きをチェック）
  def available_staff(date, slot_time, duration_minutes: 60)
    load_data
    s, e = slot_range(slot_time)
    # duration分の終了時刻
    full_end = s + duration_minutes.minutes

    w_ids = working_ids(date, s)
    # duration全体をカバーして出勤しているスタッフのみ
    w_ids = w_ids.select do |sid|
      (@sched_idx[date] || []).any? do |sc|
        sc.staff_id == sid && sc.start_time <= s && sc.end_time >= full_end
      end
    end

    # duration全体で予約が重複していないスタッフのみ
    busy_ids = (@res_idx[date] || []).select do |r|
      r.staff_id.present? && r.start_time < full_end && r.end_time > s
    end.map(&:staff_id).uniq

    free_ids = w_ids - busy_ids

    # 出張中のスタッフを除外
    trip_records = (@unavail_idx[date] || []).select { |u| u.start_time < full_end && u.end_time > s }
    if trip_records.any?
      trip_staff_ids = trip_records.select { |u| u.respond_to?(:staff_id) && u.staff_id.present? }.map(&:staff_id).uniq
      free_ids -= trip_staff_ids
    end

    free_ids &= @new_capable_ids unless @user_signed_in
    @staffs.select { |st| free_ids.include?(st.id) }
  end

  # 指名なし予約時の自動スタッフ割当
  # まさこ以外を優先し、他に空きがなければまさこを割当
  def auto_assign_staff(date, slot_time, duration_minutes: 60, is_new_customer: false)
    staff_list = available_staff(date, slot_time, duration_minutes: duration_minutes)
    return nil if staff_list.empty?

    # 新規客はcan_serve_new=trueのスタッフのみ（フィルタ済み）
    # まさこ(staff_id:1)以外を優先
    non_masako = staff_list.reject { |s| s.id == 1 }
    non_masako.any? ? non_masako.first : staff_list.first
  end

  private

  def load_data
    return if @loaded
    @loaded = true

    @service = Service.find_by!(name: @service_name)
    svc_staff_ids = StaffService.where(service: @service_name).pluck(:staff_id)
    @staffs = Staff.where(id: svc_staff_ids, active_flag: true, dismiss_flag: false).to_a
    @staff_ids = @staffs.map(&:id)
    @new_capable_ids = @staffs.select { |s| s.new_customer_flag }.map(&:id)

    # 新StaffScheduleから取得
    new_scheds = StaffSchedule.for_dates(@dates).where(staff_id: @staff_ids).to_a

    # 旧Scheduleにあって新StaffScheduleに無い分を補完（同期漏れ対策）
    old_scheds = Schedule.where(schedule_date: @dates, staff_id: @staff_ids).to_a
    if old_scheds.any?
      # 旧Scheduleを日付×スタッフでグループ化し、StaffSchedule形式に変換
      old_grouped = old_scheds.group_by { |s| [s.schedule_date, s.staff_id] }
      new_grouped = new_scheds.group_by { |s| [s.date, s.staff_id] }

      old_grouped.each do |(date, staff_id), slots|
        # 新テーブルにこの日・このスタッフのレコードがなければ補完
        next if new_grouped.key?([date, staff_id])

        spaces = slots.map(&:schedule_space).sort
        ranges = consolidate_spaces_for_fallback(spaces)
        ranges.each do |r|
          new_scheds << StaffSchedule.new(
            staff_id: staff_id, date: date,
            start_time: space_to_time_obj(r[:start]),
            end_time: space_to_time_obj(r[:end_space])
          )
        end
        Rails.logger.info("[AvailabilityService] 旧Schedule→StaffScheduleフォールバック: staff_id=#{staff_id}, date=#{date}")
      end
    end

    @sched_idx = new_scheds.group_by(&:date)
    @res_idx   = Reservation.confirmed.for_dates(@dates).includes(:user, :staff)
                            .group_by(&:date)
    @unavail_idx = ServiceUnavailability.for_dates(@dates).for_service(@service_name)
                                        .group_by(&:date)
  end

  # 旧Schedule space値の連続スロットを範囲に集約
  def consolidate_spaces_for_fallback(spaces)
    return [] if spaces.empty?
    ranges = []
    current_start = spaces.first
    current_end = spaces.first
    spaces.each_with_index do |sp, i|
      next if i == 0
      if (sp - current_end - 0.5).abs < 0.01
        current_end = sp
      else
        ranges << { start: current_start, end_space: current_end + 0.5 }
        current_start = sp
        current_end = sp
      end
    end
    ranges << { start: current_start, end_space: current_end + 0.5 }
    ranges
  end

  # space値(例: 12.0, 12.5)をTime型に変換
  def space_to_time_obj(space)
    h = space.to_i
    m = ((space - h) * 60).round
    Time.zone.parse('2000-01-01').change(hour: h, min: m)
  end

  def calc_slot(date, slot_time)
    s, e = slot_range(slot_time)
    today = Date.current
    now_h = Time.current.in_time_zone('Tokyo').hour

    return -1 if date <= today
    return -1 if date == today + 1.day && now_h >= CUTOFF_HOUR
    return -1 unless @service.bookable?

    # 営業時間内かチェック（30分枠単位で判定）
    business_end = Time.zone.parse('2000-01-01 22:00')
    return 0 if e > business_end

    case @service_name
    when 'holistic', 'wellbeing'
      calc_holistic(date, s, e)
    else
      calc_simple(date, s, e)
    end
  end

  def calc_holistic(date, s, e)
    # カレンダー表示は30分枠単位で判定（予約時に60分確保できるかは別途チェック）

    # このスロット(30分)に重複する全予約を取得
    slot_res = (@res_idx[date] || []).select do |r|
      %w[holistic wellbeing].include?(r.service) && r.start_time < e && r.end_time > s
    end

    # マシン空き = max_concurrent - 出張 - このスロットの同時予約数
    unavail_n = (@unavail_idx[date] || []).count { |u| u.start_time < e && u.end_time > s }
    machine_left = @service.max_concurrent - unavail_n - slot_res.size
    return 0 if machine_left <= 0

    # 出勤スタッフ（この30分枠をカバー）
    w_ids = (@sched_idx[date] || []).select do |sc|
      @staff_ids.include?(sc.staff_id) && sc.start_time <= s && sc.end_time >= e
    end.map(&:staff_id).uniq
    return -1 if w_ids.empty?

    # この30分枠で予約が重複するスタッフを除外
    busy_staff_ids = slot_res.select { |r| r.staff_id.present? }.map(&:staff_id).uniq
    free_ids = w_ids - busy_staff_ids

    # 出張中のスタッフを除外
    trip_records = (@unavail_idx[date] || []).select { |u| u.start_time < e && u.end_time > s }
    if trip_records.any?
      trip_staff_ids = trip_records.select { |u| u.respond_to?(:staff_id) && u.staff_id.present? }.map(&:staff_id).uniq
      free_ids -= trip_staff_ids
    end

    # マシン残りとスタッフ空きの小さい方
    free_new = free_ids.count { |id| @new_capable_ids.include?(id) }
    free_all = free_ids.size

    avail_new = [free_new, machine_left].min.clamp(0, 2)
    avail_old = [free_all, machine_left].min.clamp(0, 2)

    v = @user_signed_in ? avail_old : avail_new
    return 2 if v >= 2
    return 1 if v == 1
    0
  end

  def calc_simple(date, s, e)
    w_ids = working_ids(date, s)
    return -1 if w_ids.empty?

    # min_duration分の連続空きが確保できるかチェック
    min_end = s + @service.min_duration.minutes
    # スタッフの出勤がmin_duration分をカバーしているか
    staff_covers = (@sched_idx[date] || []).any? do |sc|
      w_ids.include?(sc.staff_id) && sc.start_time <= s && sc.end_time >= min_end
    end
    return 0 unless staff_covers

    # min_duration分の間に予約が重複していないか
    reserved = (@res_idx[date] || []).any? do |r|
      r.service == @service_name && r.start_time < min_end && r.end_time > s
    end
    reserved ? 0 : 1
  end

  def working_ids(date, slot_start)
    (@sched_idx[date] || []).select do |sc|
      @staff_ids.include?(sc.staff_id) && sc.start_time <= slot_start && sc.end_time > slot_start
    end.map(&:staff_id).uniq
  end

  def reserved_ids(date, s, e)
    (@res_idx[date] || []).select do |r|
      r.staff_id.present? && r.start_time < e && r.end_time > s
    end.map(&:staff_id).uniq
  end

  # "10:30" => [Time, Time] (slot_start, slot_end)
  def slot_range(slot_time)
    h, m = slot_time.split(':').map(&:to_i)
    base = Time.zone.parse('2000-01-01')
    s = base.change(hour: h, min: m)
    [s, s + SLOT_MINUTES.minutes]
  end
end

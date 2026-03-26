class CalendarController < ApplicationController
  def index
    # デフォルトは今日から7日間表示
    @start_date = params[:start_date]&.to_date || Date.current
    @dates = (0..6).map { |i| @start_date + i.days }
    @time_slots = generate_time_slots
    @weekly_availability = calculate_weekly_availability(@dates)
    
    # 管理者の場合は予約情報も取得
    if user_signed_in? && current_user.admin?
      @weekly_reserves = get_weekly_reserves(@dates)
      Rails.logger.info "Admin user detected: #{current_user.email}"
      Rails.logger.info "Weekly reserves count: #{@weekly_reserves.values.map(&:values).flatten.sum(&:count)}"
    else
      Rails.logger.info "Not admin or not signed in. User signed in: #{user_signed_in?}, Admin: #{user_signed_in? ? current_user.admin? : 'N/A'}"
    end
  end

  def availability
    begin
      date = params[:date]&.to_date || Date.current
      time_slot = params[:time_slot]&.to_i
      
      availability_data = calculate_slot_availability(date, time_slot)
      available_staff = get_available_staff(date, time_slot)
      
      staff_data = available_staff.map do |staff|
        {
          id: staff.id,
          name: staff.name,
          staff_type: staff.staff_type
        }
      end
      
      result = availability_data.merge(staff_list: staff_data)
      
      respond_to do |format|
        format.json { 
          render json: result, 
                 status: :ok,
                 content_type: 'application/json'
        }
        format.html { redirect_to calendar_path }
      end
    rescue => e
      Rails.logger.error "Availability error: #{e.message}"
      respond_to do |format|
        format.json { 
          render json: { error: 'サーバーエラーが発生しました' }, 
                 status: :internal_server_error,
                 content_type: 'application/json'
        }
        format.html { redirect_to calendar_path, alert: 'エラーが発生しました' }
      end
    end
  end

  private

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

    def calculate_availability(date)
      availability = {}
      
      @time_slots.each do |time_data|
        slot = time_data[:slot]
        availability[slot] = calculate_slot_availability(date, slot)
      end
      
      availability
    end

    def calculate_weekly_availability(dates)
      weekly_availability = {}
      
      dates.each do |date|
        weekly_availability[date] = {}
        @time_slots.each do |time_data|
          slot = time_data[:slot]
          weekly_availability[date][slot] = calculate_slot_availability(date, slot)
        end
      end
      
      weekly_availability
    end

    def calculate_slot_availability(date, time_slot)
      # デバッグ情報（8/14の19:00も追加）
      if date == Date.new(2025, 8, 14) && (time_slot == 0 || time_slot == 16 || time_slot == 17 || time_slot == 18)
        Rails.logger.info "=== DEBUG 8/14 time_slot #{time_slot} ==="
        Rails.logger.info "Date: #{date}"
        Rails.logger.info "Time slot: #{time_slot}"
        Rails.logger.info "Date < Date.tomorrow: #{date < Date.tomorrow}"
        Rails.logger.info "Date.tomorrow: #{Date.tomorrow}"
      end
      
      # 過去の日付は予約不可
      return { status: 'unavailable', available_staff: 0 } if date < Date.tomorrow
      
      # 翌日の予約は前日の15時までの制限をチェック
      if date == Date.tomorrow && Time.current.hour >= 15
        return { status: 'unavailable', available_staff: 0 }
      end
      
      # 利用可能なマシン数をチェック
      machine = NewMachine.find_by(name: 'holistic')
      available_machines = machine&.available_count_at(date, time_slot) || 0
      
      # デバッグ情報（8/14の19:00も追加）
      if date == Date.new(2025, 8, 14) && (time_slot == 0 || time_slot == 16 || time_slot == 17 || time_slot == 18)
        Rails.logger.info "Available machines: #{available_machines}"
      end
      
      return { status: 'unavailable', available_staff: 0 } if available_machines == 0

      # 出勤しているスタッフを取得
      working_staff = NewStaff.joins(:new_schedules)
                          .where(new_schedules: { date: date, time_slot: time_slot, working: true })
                          .where(active: true)

      # デバッグ情報（8/14の19:00も追加）
      if date == Date.new(2025, 8, 14) && (time_slot == 0 || time_slot == 16 || time_slot == 17 || time_slot == 18)
        Rails.logger.info "Working staff count: #{working_staff.count}"
        Rails.logger.info "Working staff names: #{working_staff.pluck(:name).join(', ')}"
      end

      # 誰も出勤していない場合は特別なステータスを返す
      if working_staff.empty?
        return { status: 'no_staff', available_staff: 0 }
      end

      # 既に予約が入っているスタッフを取得
      existing_reserves = NewReserve.where(date: date)
                                .where('start_time_slot <= ? AND start_time_slot + duration - 1 >= ?', 
                                      time_slot, time_slot)
      
      reserved_staff_ids = existing_reserves.pluck(:new_staff_id)
      
      # デバッグ情報（8/14の19:00も追加）
      if date == Date.new(2025, 8, 14) && (time_slot == 0 || time_slot == 16 || time_slot == 17 || time_slot == 18)
        Rails.logger.info "Existing reserves count: #{existing_reserves.count}"
        Rails.logger.info "Reserved staff IDs: #{reserved_staff_ids}"
        if existing_reserves.exists?
          Rails.logger.info "Existing reserves details: #{existing_reserves.pluck(:id, :start_time_slot, :duration, :new_staff_id)}"
        end
      end

      # 予約済みスタッフを除外した利用可能なスタッフを取得
      available_staff = working_staff.where.not(id: reserved_staff_ids)
      
      # 利用可能なスタッフ数を計算
      if user_signed_in?
        # ログイン済みユーザー: 全スタッフが対象
        available_count = available_staff.count
      else
        # 未ログインユーザー: 管理者とスタッフXのみ対象
        available_count = available_staff.where(staff_type: [:admin, :staff_x]).count
      end

      # 利用可能なマシン数も考慮
      final_available = [available_count, available_machines].min

      # デバッグ情報（8/14の19:00も追加）
      if date == Date.new(2025, 8, 14) && (time_slot == 0 || time_slot == 16 || time_slot == 17 || time_slot == 18)
        Rails.logger.info "User signed in: #{user_signed_in?}"
        Rails.logger.info "Available count: #{available_count}"
        Rails.logger.info "Final available: #{final_available}"
      end

      if final_available >= 2
        result = { status: 'excellent', available_staff: final_available }
      elsif final_available == 1
        result = { status: 'good', available_staff: final_available }
      else
        result = { status: 'unavailable', available_staff: 0 }
      end
      
      # デバッグ情報（8/14の19:00も追加）
      if date == Date.new(2025, 8, 14) && (time_slot == 0 || time_slot == 16 || time_slot == 17 || time_slot == 18)
        Rails.logger.info "Final result: time_slot = #{time_slot}, status = #{result}"
        Rails.logger.info "=== END DEBUG ==="
      end
      
      result
    end

    def get_available_staff(date, time_slot)
      # 出勤しているスタッフを取得
      working_staff = NewStaff.joins(:new_schedules)
                          .where(new_schedules: { date: date, time_slot: time_slot, working: true })
                          .where(active: true)

      # 既に予約が入っているスタッフを除外
      reserved_staff_ids = NewReserve.where(date: date)
                                .where('start_time_slot <= ? AND start_time_slot + duration - 1 >= ?', 
                                        time_slot, time_slot)
                                .pluck(:new_staff_id)
      
      available_staff = working_staff.where.not(id: reserved_staff_ids)

      unless user_signed_in?
        # 未ログインユーザーは管理者とスタッフXのみ
        available_staff = available_staff.where(staff_type: [:admin, :staff_x])
      end

      available_staff
    end

    def get_weekly_reserves(dates)
      weekly_reserves = {}
      
      dates.each do |date|
        weekly_reserves[date] = {}
        @time_slots.each do |time_data|
          slot = time_data[:slot]
          # その時間枠に重複する予約を取得
          reserves = NewReserve.includes(:user, :new_staff)
                           .where(date: date)
                           .where('start_time_slot <= ? AND start_time_slot + duration - 1 >= ?', 
                                  slot, slot)
          
          reserve_data = reserves.map do |reserve|
            {
              id: reserve.id,
              customer_name: reserve.customer_display_name,
              customer_tel: reserve.customer_display_tel,
              staff_name: reserve.new_staff.name,
              duration: reserve.duration == "thirty_minutes" ? "30分" : "60分",
              is_member: reserve.user.present?,
              member_type: reserve.user&.user_type == "1" ? "管理者" : (reserve.user.present? ? "会員" : "非会員"),
              start_time: NewSchedule.time_slot_to_time(reserve.start_time_slot)
            }
          end
          
          weekly_reserves[date][slot] = reserve_data
        end
      end
      
      weekly_reserves
    end
end
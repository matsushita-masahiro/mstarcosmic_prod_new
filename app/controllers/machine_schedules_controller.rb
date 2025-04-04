class MachineSchedulesController < ApplicationController
  layout 'main/main'
  
  before_action :set_machine, only: [:index, :new, :create]
  before_action :select_month, only: [:index, :all_schedules]
  before_action :calender_start_day, only: [:index, :all_schedules, :create] 
  before_action :authenticate_admin_user?, only: [:index, :all_schedules, :new]
    
  
  def month_select
  end
  
  def all_schedules
    logger.debug("=============== schedule all_schedules")
    
    require 'date'
    @today = Time.now.in_time_zone("Tokyo")
    @schedules = Schedule.where("schedule_date >= :date ", date: @today)    
  end
  
  def index
    require 'date'
    # before_action set_staff @staff set
    logger.debug("=============== schedule index machine_id = #{params[:machine_id]}")
    @schedule = MachineSchedule.new(machine: @machine.short_word)
    @today = Time.now.in_time_zone("Tokyo")
    @schedules = MachineSchedule.where("schedule_date >= :date ", date: @today, machine: @machine)
  end
  
  
  def new
    logger.debug("--------------------- schedule new = #{@machine}")
  end
  
  def create
    logger.debug("============================= create machine = #{params[:machine_id]}")
    
    if (defined? params[:machine][:machine_schedule])
      if (defined? @start_date)
        if machine_reserved_check(@machine.short_word, params[:machine][:machine_schedule]).empty?
          # このmachineのこの1週間のスケジュールを全削除処理し、再度check入ったspaceを作成する
          MachineSchedule.where(machine: @machine.short_word, machine_schedule_date: @start_date..(@start_date+6)).delete_all
          logger.debug("--------------------- schedule create params[:machine][:machine_schedule] = #{params[:machine][:machine_schedule]}")
          params[:machine][:machine_schedule].each do |schedule|
            schedule_arr = schedule.split("&")
            MachineSchedule.create(machine_schedule_date: schedule_arr[0], machine_schedule_space: schedule_arr[1], machine: @machine.short_word)
          end
          flash[:notice] = "出張登録できました"
          redirect_to machine_machine_schedules_path(@machine.short_word, calender_start_date: @start_date)

          # logger.debug("======= MachineSchedule.where(machine, @machine.short_word, schedule_date: start_date..(start_date+6)) = #{MachineSchedule.where(machine: @machine.short_word, machine_schedule_date: @start_date..(@start_date+6)).count}")
        else
          # 既に予約が入っていて出張登録できない
          machine_reserved_check(@machine.short_word, params[:machine][:machine_schedule]).each do |not_available_date_space|
            logger.debug("~~~~~~~~~~~~~~~~~~~ 出張登録できない枠 date = #{ not_available_date_space[0]} space = #{not_available_date_space[1]}")
            
          end
          machine_schedule_error_mail(@machine.short_word, machine_reserved_check(@machine.short_word, params[:machine][:machine_schedule]), @start_date)
        end
      end
    else
      # この1週間で１つもチェックされてない場合は全削除
      logger.debug("================== checked none start_date = #{@start_date}")
      MachineSchedule.where(machine: @machine.short_word, machine_schedule_date: @start_date..(@start_date+6)).delete_all
      flash[:notice] = "出張修正できました"
      # schedule/indexへ
      redirect_to machine_machine_schedules_path(@machine.short_word, calender_start_date: @start_date)
    end
  end  
  
  def edit
  end
  
  
  
  private
  
     def set_machine
       @machine = Machine.find_by(short_word: params[:machine_id])
     end
     
     def select_month
       if params[:year].present? && params[:month].present? 
          @year = params[:year]
          @month = params[:month]
        else
          
        end
     end
     
     def calender_start_day
        # 日付ではないデータが直打ちされた時の対処のif
        # logger.debug("=================== schedule calender_start_day = #{params[:calender_start_date]}")
        if (defined? params[:calender_start_date]) && date_valid?(params[:calender_start_date])
          # logger.debug("--------------------------- calender_start = not nil #{params[:calender_start_date]}")
          @start_date = DateTime.parse(params[:calender_start_date])
          # 今日から5週間の以外前後の日をURLから直打ちしたときの対処(scheduleでは5週間以降も表示する)
          # if @start_date > Date.today + 28
          #   # @start_date = Date.today + 35
          # 今日以前は今日
          if @start_date < Date.today
            @start_date = Date.today
          end
        else
          # logger.debug("~~~~~~~~~~~~~~~~~ Time.current = #{Time.current.since(1.days)}")
          # logger.debug("~~~~~~~~~~~~~~~~~ Time.now     = #{Time.now}")
          # logger.debug("--------------------------- calender_start =  nil or false")
          # @start_date = DateTime.current.in_time_zone("Tokyo")
          # logger.debug("--------------------------- today =  #{@start_date}")
          @start_date = Date.today
        end
     end 
     
    # 2022/08/28 add
     def machine_reserved_check(machine, checked_array)
      # マシン全台数
       machine_numbers = Machine.find_by(short_word: machine).number_of_machine
       
       available_flag = true
       not_available_array = []
       
        # 例[2022-08-31, 11.0, 1] 
        checked_array.each do |checked_date_space|
            checked_date_space_arr = checked_date_space.split("&")
            logger.debug("~~~~~~~~~~~~~~~~~~~~~~~~~~~ checked_date_space_arr = #{checked_date_space_arr}")
            # その枠のそのマシンの既予約数
             machine_reserved_numbers = Reserve.where(machine: machine, reserved_date: checked_date_space_arr[0], reserved_space: checked_date_space_arr[1]).count
            # その枠の出張既登録数（今は１台しか出張登録考えてないので基本はゼロ）
             machine_moved_numbers = MachineSchedule.where(machine_schedule_date: checked_date_space_arr[0], machine_schedule_space: checked_date_space_arr[1], machine: machine).count
            # その枠の出張可能な台数
             #　すでにその枠に出張登録されていた場合
             masako_reserved = Reserve.find_by(reserved_date: checked_date_space_arr[0], reserved_space: checked_date_space_arr[1], staff_id: 1)
             logger.debug("|||||||||||||||||||| masako_reserved = #{masako_reserved}")
             if machine_moved_numbers == 1
               machine_moved_numbers  = 0
             end
             available_machine_numbers = machine_numbers - machine_reserved_numbers - machine_moved_numbers
             logger.debug("======================== available_machine_numbers = #{available_machine_numbers} machine_reserved_numbers = #{machine_reserved_numbers} machine_moved_numbers = #{machine_moved_numbers}")
            # 出張不可能な枠が１つでもある場合
            if available_machine_numbers <= 0 || masako_reserved
              not_available_array << [checked_date_space_arr[0], checked_date_space_arr[1]]
              available_flag = false
            end
          
        end # each end
       
       
       if available_flag
         return not_available_array
       else
         return not_available_array
       end
     end
     
     def machine_schedule_error_mail(machine, info, calender_start_day)
           respond_to do |format|
                AdminMailer.machine_schedule_error(machine, info).deliver
                @flash_msg = "出張登録不可な枠がありましたメールを確認下さい"
                format.html { redirect_to machine_machine_schedules_path(machine, calender_start_date: calender_start_day), alert: @flash_msg }
          end
     end
end

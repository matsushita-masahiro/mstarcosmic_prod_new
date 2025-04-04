class SchedulesController < ApplicationController
  
  layout 'main/main'
  
  before_action :set_staff, only: [:index, :new]
  before_action :select_month, only: [:index, :all_schedules]
  before_action :calender_start_day, only: [:index, :all_schedules, :create] 
  before_action :authenticate_staff, only: [:index, :all_schedules]
    
  
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
    logger.debug("=============== schedule index staff_id = #{params[:staff_id]}")
    @schedule = @staff.schedules.new
    @today = Time.now.in_time_zone("Tokyo")
    @schedules = @staff.schedules.where("schedule_date >= :date ", date: @today)
    
    
  end
  
  
  def new
    logger.debug("--------------------- schedule new = #{@staff.name}")
  end
  
  def create
    logger.debug("============================= create staff = #{params[:staff_id]}")
    @staff = Staff.find(params[:staff_id])
    if (defined? params[:staff][:schedule])
      if (defined? @start_date)
          # このstaffのこの1週間のスケジュールを全削除処理し、再度check入ったspaceを作成する
          @staff.schedules.where(schedule_date: @start_date..(@start_date+6)).delete_all
          # logger.debug("--------------------- schedule create calender_start_date = #{params[:calender_start_date]}")
          params[:staff][:schedule].each do |schedule|
            schedule_arr = schedule.split("&")
            @staff.schedules.create(schedule_date: schedule_arr[0], schedule_space: schedule_arr[1])
            # logger.debug("--------------------- schedule create params check status= #{schedule_arr}")
            # logger.debug("--------------------- schedule create params check status= #{schedule_arr[2]}")
            # logger.debug("--------------------- schedule create params date 型= #{Date.strptime(schedule_arr[0])}")
          end
          logger.debug("======= Schedule.where(schedule_date: start_date..(start_date+6)) = #{Schedule.where(schedule_date: @start_date..(@start_date+6)).count}")
      end
    else
      # この1週間で１つもチェックされてない場合は全削除
      logger.debug("================== checked none start_date = #{@start_date}")
      @staff.schedules.where(schedule_date: @start_date..(@start_date+6)).delete_all
    end
    # schedule/indexへ
    redirect_to staff_schedules_path(@staff,calender_start_date: @start_date)
  end  
  
  # schedule create old past 2022/2/10 
  # def create
  #   logger.debug("============================= create user = #{params[:user_id]}")
  #   @user = User.find(params[:user_id])
  #   if (defined? params[:user][:schedule])
  #     if (defined? @start_date)
  #         # このUserのこの1週間のスケジュールを全削除処理し、再度check入ったspaceを作成する
  #         @user.schedules.where(schedule_date: @start_date..(@start_date+6)).delete_all
  #         # logger.debug("--------------------- schedule create calender_start_date = #{params[:calender_start_date]}")
  #         params[:user][:schedule].each do |schedule|
  #           schedule_arr = schedule.split("&")
  #           @user.schedules.create(schedule_date: schedule_arr[0], schedule_space: schedule_arr[1])
  #           # logger.debug("--------------------- schedule create params check status= #{schedule_arr}")
  #           # logger.debug("--------------------- schedule create params check status= #{schedule_arr[2]}")
  #           # logger.debug("--------------------- schedule create params date 型= #{Date.strptime(schedule_arr[0])}")
  #         end
  #         logger.debug("======= Schedule.where(schedule_date: start_date..(start_date+6)) = #{Schedule.where(schedule_date: @start_date..(@start_date+6)).count}")
  #     end
  #   else
  #     # この1週間で１つもチェックされてない場合は全削除
  #     logger.debug("================== checked none start_date = #{@start_date}")
  #     @user.schedules.where(schedule_date: @start_date..(@start_date+6)).delete_all
  #   end
  #   # schedule/indexへ
  #   redirect_to user_schedules_path(@user,calender_start_date: @start_date)
  # end
  
  
  def edit
  end
  
  
  
  private
  
     def set_staff
       @staff = Staff.find_by(id: params[:staff_id])
     end
     
     def select_month
       if params[:year].present? && params[:month].present? 
          @year = params[:year]
          @month = params[:month]
        else
          
        end
     end
     
     def authenticate_staff
       if current_user.user_type == "10" || current_user.user_type == "1"
         return true
       else
         flash[:alert] = "権限がありません"
         redirect_back(fallback_location: root_path)
       end
     end
     
     
     def calender_start_day
        # 日付ではないデータが直打ちされた時の対処のif
        logger.debug("=================== schedule calender_start_day = #{params[:calender_start_date]}")
        if (defined? params[:calender_start_date]) && date_valid?(params[:calender_start_date])
          logger.debug("--------------------------- calender_start = not nil #{params[:calender_start_date]}")
          @start_date = DateTime.parse(params[:calender_start_date])
          # 今日から5週間の以外前後の日をURLから直打ちしたときの対処(scheduleでは5週間以降も表示する)
          # if @start_date > Date.today + 28
          #   # @start_date = Date.today + 35
          # 今日以前は今日
          if @start_date < Date.today
            @start_date = Date.today
          end
        else
          logger.debug("~~~~~~~~~~~~~~~~~ Time.current = #{Time.current.since(1.days)}")
          logger.debug("~~~~~~~~~~~~~~~~~ Time.now     = #{Time.now}")
          logger.debug("--------------------------- calender_start =  nil or false")
          # @start_date = DateTime.current.in_time_zone("Tokyo")
          logger.debug("--------------------------- today =  #{@start_date}")
          @start_date = Date.today
        end
     end     
     
     
end

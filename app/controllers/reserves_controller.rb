class ReservesController < ApplicationController
  
    layout 'main/main'
    
    include ApplicationHelper
    before_action :authenticate_user!, except: [:new_cust, :new_cust_other, :new, :create]
    before_action :redirect_edit_user, oniy: [:index]
    before_action :calender_start_day, only: [:staff, :index, :destroy, :delete, :new_cust, :new_cust_other] 
    before_action :reject_reserve_new, only: [:create]

    def new
        if user_signed_in?
          @user = current_user
        else
          @user = nil
        end
        
        @reserve = Reserve.new
        @date = params[:date]
        @frame = params[:frame]
        @start_date = params[:start_date]
        # 新は下記をコメント
        @staff = Staff.find(params[:staff_id])
        @machine = params[:machine]

        # url直打ち(reserves/new)防止 
        return redirect_to reserves_path if @date.nil?

        respond_to do |format|
            # format.html
            format.js
        end
    end
  
    def new_staff
        @reserve = Reserve.new
        @date = params[:date]
        @frame = params[:frame]
        @start_date = params[:start_date]
        @staff = Staff.find(params[:staff_id])

        # url直打ち(reserves/new)防止 
        return redirect_to reserves_path if @date.nil?

        respond_to do |format|
            # format.html
            format.js
        end
    end  
  
  # machine時代のcreateアクション
  def create
    
    if user_signed_in? || !User.find_by(email: reserve_params[:email])  # ログインしてる または まだに存在していないアカウント
        logger.debug("================== reserve_params = #{reserve_params}")
        
        save_flag = true
        error_msg = ""
        
        @staff = Staff.find(reserve_params[:staff_id])
        if user_signed_in? 
          @user = User.find(current_user.id)
        else
          # new_customer
          new_customer_flag = true
          # 新しいユーザーを登録する
          @user = User.create(name: reserve_params[:name], tel: reserve_params[:tel], gender: reserve_params[:gender], name_kana: reserve_params[:name_kana], email: reserve_params[:email], password: "123456", user_type: 11)
          logger.debug("================== user created = #{@user.id}")
          unless @user
            error_msg = "登録済みのメールアドレスの為"
            save_flag = false
          end
        end
        
        
        
        if save_flag
            
            logger.debug("=================== at reserves_new_controller create ")
          
            @frames = (params[:reserve][:frames].to_i)/30    # frames ( 60分:2 90分:3 120分:4）
            can_reserve_flag = true
                
            # 予約が算命学の場合次の枠で聖子が空いてなければ予約不可にする
            if (@staff.id == 1 && reserve_params[:machine] == "o") || reserve_params[:email] == "s"
              logger.debug("--------------- can_reserve_sanmei_next_space before")
              able_reserve_sanmei_this_space = available_space(params[:reserve][:reserved_date], (params[:reserve][:reserved_space].to_f), params[:reserve][:staff_id], params[:reserve][:machine])
              able_reserve_sanmei_next_space = available_space(params[:reserve][:reserved_date], (params[:reserve][:reserved_space].to_f + 0.5), params[:reserve][:staff_id], params[:reserve][:machine])
              if able_reserve_sanmei_next_space && able_reserve_sanmei_this_space
                logger.debug("--------------- can_reserve_sanmei_next_space = #{able_reserve_sanmei_next_space}")
                can_reserve_flag = true
              else
                error_msg = "算命学の予約は６０分必要です。"
                can_reserve_flag = false
                logger.debug("--------------- can_reserve_sanmei_next_space else else = #{able_reserve_sanmei_next_space}")
              end
            else
              can_reserve_flag = true
                logger.debug("--------------- can_reserve_sanmei_next_space else 無関係= staff_id = #{@staff.id} machine = #{reserve_params[:machine]}")
            end
        
            if can_reserve_flag
            
              j = 0  # 保存レコード数初期化
              available_flag = false  #　すでに他の人に予約されてた時のフラグ(予約しようとしているスペースの１つでも予約されてたらfalse)
              
              @frames.times do |i|
                
                 available_flag = available_space(params[:reserve][:reserved_date], (params[:reserve][:reserved_space].to_f + (0.5*i)), params[:reserve][:staff_id], params[:reserve][:machine])
                 logger.debug("^^^^^^^^^^^^^^^^^^^^^^^^^ available_flag = #{available_flag}")
              end
              
              if available_flag
                  @frames.times do |i|
                    @reserve = Reserve.new(reserve_params)
                    if !user_signed_in?
                     @reserve.user_id = @user.id
                    end
                    @reserve.reserved_space = params[:reserve][:reserved_space].to_f + (0.5*i)
                    # add code for new_customer 2023/08/12 from 65行目
                    if new_customer_flag
                      @reserve.new_customer = true
                    end
                    if @reserve.save
                      # 予約枠開始時刻をflashに設定
                      if i === 0
                        @reserve.root_reserve_id = @reserve.id
                        @this_root_reserve_id = @reserve.id
                        @flash_reserve_space = @reserve.reserved_space
                        @reserve.save
                        @root_reserve = @reserve
                        logger.debug("------------------ flash_reserve_space = #{@flash_reserve_space}")
                      else
                        @reserve.root_reserve_id = @this_root_reserve_id
                        @reserve.save
                      end
                      j += 1
                    end
                  end
              end
            end
        
            
            if @frames == j && can_reserve_flag
              save_flag = true
            else
              save_flag = false
            end
      else
        
      end

    
        respond_to do |format|
          if save_flag
            SampleMailer.send_when_create_new(@root_reserve,@user,@frames).deliver
            AdminMailer.send_when_reserved_new(@root_reserve,@user,@frames).deliver
            @flash_msg = "#{@reserve.reserved_date.to_date.strftime("%Y年 %-m月 %-d日")}の#{display_time(@flash_reserve_space)}〜（#{@frames.to_i*30}分）予約承りました"
            logger.debug("------------ create success start_date = #{params[:reserve][:start_date]}")
            logger.debug("------------ create staff_id =  #{reserve_params[:staff_id]}")
            if (reserve_params[:machine] == "h" || reserve_params[:machine] == "w")
              if user_signed_in?
                format.html { redirect_to reserves_path(staff_id: reserve_params[:staff_id], machine: reserve_params[:machine],calender_start_date: params[:reserve][:start_date]), notice: @flash_msg }
                # format.html { redirect_to "/reserves/#{reserve_params[:staff_id]}/index?calender_start_date=#{params[:reserve][:start_date]}", notice: @flash_msg }
                format.json { render :index, status: :created, location: @reserve }
              else
                format.html { redirect_to reserves_new_cust_path(staff_id: reserve_params[:staff_id], machine: reserve_params[:machine],calender_start_date: params[:reserve][:start_date]), notice: @flash_msg }
                # format.html { redirect_to "/reserves/#{reserve_params[:staff_id]}/index?calender_start_date=#{params[:reserve][:start_date]}", notice: @flash_msg }
                format.json { render :index, status: :created, location: @reserve }              
              end
            else
              if user_signed_in?
                format.html { redirect_to reserves_path(staff_id: reserve_params[:staff_id], machine: reserve_params[:machine],calender_start_date: params[:reserve][:start_date]), notice: @flash_msg }
                # format.html { redirect_to "/reserves/#{reserve_params[:staff_id]}/index?calender_start_date=#{params[:reserve][:start_date]}", notice: @flash_msg }
                format.json { render :index, status: :created, location: @reserve }
              else
                format.html { redirect_to reserves_new_cust_other_path(staff_id: reserve_params[:staff_id], machine: reserve_params[:machine],calender_start_date: params[:reserve][:start_date]), notice: @flash_msg }
                # format.html { redirect_to "/reserves/#{reserve_params[:staff_id]}/index?calender_start_date=#{params[:reserve][:start_date]}", notice: @flash_msg }
                format.json { render :index, status: :created, location: @reserve }              
              end              
            end
          else
            logger.debug("------------ create error です")
            # render用flash
            @flash_msg = error_msg + "予約できませんでした"
            # format.html { render :index }
            format.html { redirect_to reserves_path(staff_id: reserve_params[:staff_id], calender_start_date: params[:reserve][:start_date], machine: reserve_params[:machine]), alert: @flash_msg }
            # format.html { redirect_to "/reserves/#{reserve_params[:machine]}/index?calender_start_date=#{params[:reserve][:start_date]}", alert: "予約できませんでした" }
            format.json { render json: @reserve.errors, status: :unprocessable_entity }
          end
        end  
    else
    # already user
      flash[:alert] = "すでに登録済みです。ログイン後に予約して下さい"
      logger.debug(flash[:alert])
      redirect_to new_user_session_path
    end
    

  end    # create end 


  
  def index
    logger.debug("------------------ reserve index machine_id  = #{params[:machine]}")
    require 'date'
    @reserve = Reserve.new
    @today = Time.now.in_time_zone("Tokyo")
    @reserves = Reserve.where("reserved_date >= :date ", date: @today)
    # 新予約は下記コメント外す
    if params[:staff_id].present?
      @staff = Staff.find(params[:staff_id])   # 1:聖子 2:ゆうき 3:花香 4:奈緒 5:夏子 6:由香 7:可奈 8:佐藤
    else
      if params[:machine] == "o" || params[:machine] == "e"
        # エステのスタッフ(2023/9/24時点はなるみ)
        @staff = Staff.find(StaffMachineRelation.find_by(machine: "e").staff_id)
      else
        @staff = Staff.find(0)
      end
    end
    if params[:machine] == "h" 
      @machine = "h"
    elsif params[:machine] == "w"
      @machine = "h"
      # 2023/1/27 wellbeing 病気の方にレンタル中にてwellbeingの予約ができないようにした。
      # @machine = "w"
    else
      @machine = params[:machine]
    end
    @reserves_by_staff = Reserve.where("reserved_date >= :date ", date: @today)
    staffs = StaffMachineRelation.where(machine: @machine).order(id: :desc).pluck(:staff_id)
    @staffs = Staff.where(id: staffs, active_flag: true).order(:id)


    logger.debug("================= @staffs = #{@staffs}")
    @selected = ""
  end
  
  def new_cust_other
    logger.debug("------------------ reserve index machine_id  = o のみ")
    require 'date'
    if params[:machine].present?
      @machine = params[:machine]
    else
      @machine = "e"
    end
    
    @staff = @machine == "b" ? Staff.find(StaffMachineRelation.find_by(machine: "b").staff_id) : Staff.find(StaffMachineRelation.find_by(machine: "e").staff_id)
    @reserve = Reserve.new
    @today = Time.now.in_time_zone("Tokyo")
    @reserves = Reserve.where("reserved_date >= :date ", date: @today)
    machine = ["o", "e", "b"]      # machinaはその他かエステeか鍼・整体b
    @reserves_by_staff = Reserve.where("reserved_date >= :date ", date: @today)
    staffs = StaffMachineRelation.where(machine: machine).order(id: :desc).pluck(:staff_id)
    @staffs = Staff.where(id: staffs, active_flag: true).order(:id)

    logger.debug("================= @staffs = #{@staffs}")
    @selected = ""
    
  end
  
  def new_cust
    
    require 'date'
    @reserve = Reserve.new
    @today = Time.now.in_time_zone("Tokyo")
    @reserves = Reserve.where("reserved_date >= :date ", date: @today)
    @staff = Staff.find(0) # 指定なしで2023/9/8時点ではstaffは聖子か花香
    @machine = "h"       # machinaはホリスティックのみ
    logger.debug("------------------ reserve index machine_id  = h のみ @machine = #{@machine}}")
    @reserves_by_staff = Reserve.where("reserved_date >= :date ", date: @today)
    staffs = StaffMachineRelation.where(machine: @machine).order(id: :desc).pluck(:staff_id)
    @staffs = Staff.where(id: staffs, active_flag: true).order(:id)


    logger.debug("================= @staffs = #{@staffs}")
    @selected = "" 
  end
  
  def staff
    require 'date'
    @reserve = Reserve.new
    @today = Time.now.in_time_zone("Tokyo")
    @reserves = Reserve.where("reserved_date >= :date ", date: @today)
    @staff = Staff.find(params[:staff_id])   # 1:管理者 2:ゆうき
    @reserves_by_staff = Reserve.where("reserved_date >= :date ", date: @today, staff_id: @staff.id)
  end
  
 
  
  def make_holiday
    logger.debug("----------------------- params[:start_date] = #{params[:start_date]}")
    logger.debug("----------------------- params[:space] = #{params[:space].to_f/10}")
    space = params[:space].to_f/10
    @reserve = Reserve.new(user_id: 0,reserved_date: params[:date],reserved_space: space, remarks: "休��")

    if @reserve.save
        flash[:notice] = "#{params[:date].to_date.strftime("%Y年 %-m月 %-d日")}の#{display_time(space)}〜を休みにしました"
        redirect_to reserves_path(calender_start_date: params[:start_date].to_date)
    else
        flash[:notice] = "休み入力できませんでした"
        render "reserves/index"
    end   
  end
  
  
  # reservations ->> reserves データ移行
  def data_conversion
   @reserves = Reserve.all
   admin = User.find_by(email: ENV['USER_EMAIL'])
   @staff = Staff.find_by(user_id: admin.id)
   @reserves.update_all(staff_id: @staff.id)
   
    flash[:notice] = "ReserveDBのstaff_idカラムを#{@reserves.count}件のstaff.idを#{@staff.id}に一括更新しました"
    redirect_to reserves_path
  end
  
  # 未来予約
  def my_reserved
      # logger.debug("============== 遷移元 at my_reserved　#{Rails.application.routes.recognize_path(request.referrer)[:action]}")
      if User.find(current_user.id).user_type == "1"
          selected_root_reserve(Reserve.where('reserved_date >= ?', Date.today).where.not(user_id: 0).order(:reserved_date).order(:reserved_space))
      else 
          selected_root_reserve(Reserve.where('user_id = ? and reserved_date >= ?',current_user.id, Date.today).order(:reserved_date).order(:reserved_space))
      end
  end  
  
  # 予約の解除（削除）　reservesの親・子予約関連レコード削除する
  def destroy
        @reserve = Reserve.find_by(id: params[:id])
        @reserves = Reserve.where(root_reserve_id: params[:id])
        # 遷移元のURLアクション
        # fromAction = Rails.application.routes.recognize_path(request.referrer)[:action]
        if @reserve
            if @reserves.destroy_all
              flash[:notice] = "予約を取り消しました"
              redirect_to reserves_my_reserved_path
            else
              flash[:notice] = "予約を取り消せませんでした"
              render 'reserves/my_reserved'
            end

        else 
              render 'reserves/my_reserved'
        end
  end 
  
  # 休日の解除（削除）
  def delete
        @reserve = Reserve.find_by(id: params[:id])
        if @reserve.destroy
          flash[:notice] = "休みを取り消しました"
          redirect_to reserves_path(calender_start_date: @start_date)
        else
          flash[:notice] = "休みを取り消せませんでした"
          redirect_back(fallback_location: reserves_path)
        end
  end    
  
  
  
  
  

  private 
    def reserve_params
      params.require(:reserve).permit(:user_id, :reserved_date, :reserved_space, :remarks, :staff_id, :start_date, :frames, :machine, :name, :name_kana, :email, :tel, :gender)
    end
  
    
    def calender_start_day
      # 日付ではないデータが直打ちされた時の対処のif

      if (defined? params[:calender_start_date]) && date_valid?(params[:calender_start_date])
        logger.debug("--------------------------- calender_start = not nil #{params[:calender_start_date]}")
        @start_date = DateTime.parse(params[:calender_start_date])
        # 今日から5週間の以外前後の日をURLから直打ちしたときの対処
        if @start_date > Date.today + 28
          @start_date = Date.today + 35
        elsif @start_date < Date.today
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
    
    # カレンダー表示（URL直打ちで日付でない情報が入力されたときにfalseを返す）
    # 2020/11/2 application_controller に移動 at starbacks sakurashinmachi
    # def date_valid?(str)
    #   !! Date.parse(str) rescue false
    # end
    

    # reservesテーブルからidとroot_reserve_idが同じ物だけセット(予約親レコード)
    def selected_root_reserve(reserves_instance)
      @reserves = []
      reserves_instance.each do |reserve|
        if reserve.id === reserve.root_reserve_id
         @reserves << reserve
        end
      end
      return @reserves
    end
    
    
    # 0:00-9:00の間に予約された時はエラー処理 
    # def reject_reserve
    #   # 予約入力時刻がDate.todayがreserved_dateの前日で15:00以前なら予約不可にする
    #   if params[:reserve][:reserved_date].to_date-1 == Date.today && Time.now.in_time_zone("Tokyo").hour >= 15
    #     logger.debug("-------------- 0:00-9:00? #{Time.now.in_time_zone("Tokyo").hour}:#{Time.now.in_time_zone("Tokyo").min}")
    #     logger.debug("-------------- reject_reserve reserved_date = #{params[:reserve][:reserved_date].to_date}..今=#{Time.now.in_time_zone("Tokyo")}")
    #     flash[:alert] = "15時を過ぎると翌日の予約はできません"
    #     redirect_back(fallback_location: root_path)
    #   else
    #     logger.debug("-------------- accept_reserve reserved_date = #{params[:reserve][:reserved_date].to_date}..今=#{Time.now.in_time_zone("Tokyo")}")
    #   end
    # end
    
    # 翌日の予約は15時以降は不可,当日予約不可
    def reject_reserve_new
      tokyo_time = Time.now.in_time_zone("Tokyo")
      today = Time.now.in_time_zone("Tokyo").to_date
      logger.debug("今の時間 = #{tokyo_time}")
      reserved_date = params[:reserve][:reserved_date].to_date rescue nil
    
      if reserved_date.present?
        if ( reserved_date == ( today + 1 )  && tokyo_time.hour >= 15 )
          logger.debug("-------------- reject_reserve reserved_date = #{reserved_date}..今=#{tokyo_time}")
          flash[:alert] = "15時を過ぎると翌日の予約はできません"
          redirect_back(fallback_location: root_path)
        elsif ( reserved_date == today ) 
          flash[:alert] = "当日の予約はできません"
          redirect_back(fallback_location: root_path)          
        else
          logger.debug("-------------- accept_reserve reserved_date = #{reserved_date}..今=#{tokyo_time}.. today = #{today}")
        end
      else
        flash[:alert] = "予約日が不正です"
        redirect_back(fallback_location: root_path)
      end
    end
    
    
    
    # calender3用
    def reserved_status(staff, date, space)
        if schedule = Schedule.find_by(user_id: staff.user_id, schedule_date: date, schedule_space: space)  # 出勤
            if reserve = Reserve.find_by(staff_id: staff.id, reserved_date: date, reserved_space: space) # 予約有
               return false
            else #出勤&予約なし
               return true
            end
        else  # 欠勤
            return false
        end
    end 
    
    
    
    def available_space(date, space, staff_id, machine)
      
          # machine台数未満の予約数なら予約できる**** 
          if Reserve.where(reserved_date: date, reserved_space: space, machine: machine).count < Machine.find_by(short_word: machine).number_of_machine
          
              if staff_id.to_i == 0
                logger.debug("^^^^^^^^^^^^^^ 指名なし")
               # 指名なし
               # 出勤している全スタッフ数(active_staff_count)
                # 鹿田が出勤していて算命学の予約入ってない場合はプラス1
                if Schedule.find_by(schedule_date: date, schedule_space: space, staff_id: 1) && !Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: 1, machine: "o")
                  # active_staff_count = Schedule.where(schedule_date: date, schedule_space: space).count + 1
                  # 2025/5/7 鹿田が出勤しててても鹿田も１人として考える
                  active_staff_count = Schedule.where(schedule_date: date, schedule_space: space).count
                else
                  active_staff_count = Schedule.where(schedule_date: date, schedule_space: space).count
                end
                
                # 既に予約されているスタッフ数
                reserved_staff_count = Reserve.where(reserved_date: date, reserved_space: space).count
                
                # 予約可能数
                available_count = active_staff_count - reserved_staff_count
                logger.debug("^^^^^^^^^^^^^^ active_staff_count  #{active_staff_count} reserved_staff_count =#{reserved_staff_count} ")
                logger.debug("^^^^^^^^^^^^^^ available_count 指名なし #{available_count}")
              else
                logger.debug("^^^^^^^^^^^^^^ 指名あり")
                if Schedule.find_by(schedule_date: date, schedule_space: space, staff_id: staff_id)
                  if staff_id.to_i == 1
                    # 鹿田が指名された時
                    active_staff_count = Schedule.where(schedule_date: date, schedule_space: space, staff_id: staff_id).count + 1
                    logger.debug("^^^^^^^^^^^^^^ 指名あり active_staff_count = #{active_staff_count}")
                  else
                    # 鹿田以外の指名
                    active_staff_count = Schedule.where(schedule_date: date, schedule_space: space, staff_id: staff_id).count
                  end
                else
                  # 指名スタッフが出勤してない
                  active_staff_count = 0
                end
                
                # 既に予約されているスタッフ数
                reserved_staff_count = Reserve.where(reserved_date: date, reserved_space: space, staff_id: staff_id).count 
                
                # 既にその枠が予約で満杯になっている場合
                if Schedule.find_by(schedule_date: date, schedule_space: space, staff_id: 1)
                  all_schedules = Schedule.where(schedule_date: date, schedule_space: space).count + 1
                else
                  all_schedules = Schedule.where(schedule_date: date, schedule_space: space).count
                end
                
                all_reserves = Reserve.where(reserved_date: date, reserved_space: space).count
                
                
                # 予約可能数
                if (all_schedules - all_reserves) <= 0
                  logger.debug("^^^^^^^^^^^^^^ available_count 指名あり (all_schedules - all_reserves) <= 0")
                  available_count = 0
                else
                  logger.debug("^^^^^^^^^^^^^^ available_count 指名あり (all_schedules - all_reserves) > 0")
                  available_count = active_staff_count - reserved_staff_count
                end
                logger.debug("^^^^^^^^^^^^^^ available_count 指名あり #{available_count}")
              end
              
              # 算命学の予約は鹿田の予約が何か１件でも入っていたら予約できない
              if machine == "o" && staff_id.to_i == 1
                logger.debug("~~~~~~~~~~~~~~~~ machine == o && staff_id == 1")
                masako_reserved = Reserve.find_by(reserved_date: date, reserved_space: space, staff_id: 1)
                masako_scheduled = Schedule.find_by(schedule_date: date, schedule_space: space, staff_id: 1)
              
                can_sanmei_reserve = false
                # 鹿田が出勤してて
                if masako_scheduled
                  # 鹿田の予約が1件ある
                  if masako_reserved
                    logger.debug("~~~~~~~~~~~~~~~~ 算命学予約あり")
                    can_sanmei_reserve = false
                  else
                    logger.debug("~~~~~~~~~~~~~~~~ 算命学予約なし")
                    # 鹿田以外の空きスタッフ数 >　指名なしW,H予約数  
                    if (Schedule.wh_attendance_staffs_array(date,space) - Reserve.nominated_staff_array(date,space)).count > Reserve.nonnominated_reserved_count(date,space)
                      can_sanmei_reserve = true
                    else
                      can_sanmei_reserve = false
                    end
                  end
                end
              end
              
           

              
                
              # 戻り値は予約可能フラグ
              if machine == "o" && staff_id.to_i == 1
                if available_count >= 1 && can_sanmei_reserve
                  logger.debug("?????????? 111")
                  return true
                else
                  logger.debug("?????????? 2")
                  return false
                end
              else
                if available_count >= 1
                  logger.debug("?????????? 3 machine == #{machine} && staff_id = #{staff_id}")
                  return true
                else
                  logger.debug("?????????? 4")
                  return false
                end
              end

          
          else
            # すでに2台予約済み
            logger.debug("^^^^^^^^^^^^^^^ そのマシンは満杯です machine = #{machine}")
            return false
          end

      
    end  
    
    
    def redirect_edit_user
      if registration_completed?.size > 0
        redirect_to edit_user_path(current_user)
      end
    end
     

  
end

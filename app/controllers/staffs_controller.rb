class StaffsController < ApplicationController
  
  layout 'main/main'
  
  before_action :authenticate_staff_user?
  
  def activate
    @staff = Staff.find(params[:id])
    @staff.update(active_flag: true)
    redirect_to staff_schedules_path(@staff)
  end
  
  def nonactivate
    @staff = Staff.find(params[:id])
    @staff.update(active_flag: false)    
    redirect_to staff_schedules_path(@staff)
  end
  
  def new
    # user.id = 0 は休みなので選択からはずす　　user_type 1:管理者  10:施術者
    @already_staffs = Staff.all.pluck(:user_id)
    @already_staffs =  @already_staffs + [1144,1145]
    @users = User.where.not(id: 0).where(user_type: ["1","10"]).where.not(id: @already_staffs).pluck(:id, :name)
    @staff = Staff.new
    registored_staff_array = StaffMachineRelation.where.not(id: 0).where.not(staff_id: 0).select(:staff_id).distinct.pluck(:staff_id)
    @staffs = Staff.where(dismiss_flag: false).where.not(id: 0).order(:id)
    @staff_machine_relations = StaffMachineRelation.where.not(staff_id: 0).order(:id)
    @staff_machine_relation = @staff.staff_machine_relations.build
  end
  
  
  def create
    
    logger.debug("============================== staff_params  = #{staff_params}}")
    logger.debug("============================== staff_params machine = #{params[:staff][:staff_machine_relations_attributes]["0"][:machine]}}")
    
    @staff = Staff.new(staff_params)
    
    if @staff.save
      flash[:notice] = "#{@staff.name}のスタッフ登録を完了しました"
      redirect_to "/admin/staffs"
    else
      # render :new
      flash[:notice] = "スタッフ登録できませんでした"
      redirect_to new_staff_path
    end
  end
  
  
  def index
    # 指名なし0でもない 解任(dismiss_flug: true)もされていない
    @staffs = Staff.where.not(id: 0, dismiss_flag: true).order(:id)
  end
  
  
  def destroy
    @staff = Staff.find(params[:id])
    logger.debug("解任対象staff= #{@staff.name}")
    @schedules = @staff.schedules
    @staff_machine_relations = @staff.staff_machine_relations
    logger.debug("^^^^^^^ @staff_machine_relation count= #{@staff_machine_relations.count}")
    @schedules.destroy_all
    @staff_machine_relations.destroy_all
    # reserve情報にstaff_idがあるので、物理削除せずに解任フラグをtrueにする
    if @staff.update(dismiss_flag: true)
     flash[:notice] = "スタッフ解任しました"
     redirect_to "/admin/staffs"
   else
     flash[:alert] = "スタッフ解任できませんでした"
     redirect_back(fallback_location: root_path)
   end
  end
  
  def update
    @staff = Staff.find(params[:id])
    logger.debug("就任対象staff= #{@staff.name}")
    if @staff.update(dismiss_flag: false, active_flag: true)
     flash[:notice] = "再度スタッフ就任しました"
     redirect_to "/admin/staffs"      
    else
     flash[:alert] = "スタッフ就任できませんでした"
     redirect_back(fallback_location: root_path)      
    end
  end
  
  def update_info
    @staff = Staff.find(params[:id])
    if @staff.update(staff_info_params)
      flash[:notice] = "#{@staff.name}のスタッフ情報を更新しました"
    else
      flash[:alert] = "スタッフ情報を更新できませんでした"
    end
    redirect_to new_staff_path
  end

  def fire 
    @staff = Staff.find(params[:id])
    # 関連する全テーブルの参照を解除・削除してから物理削除
    @staff.reserves.update_all(staff_id: 0)
    Reservation.where(staff_id: @staff.id).update_all(staff_id: nil)
    StaffSchedule.where(staff_id: @staff.id).destroy_all
    StaffService.where(staff_id: @staff.id).destroy_all
    @staff.staff_machine_relations.destroy_all
    @staff.schedules.destroy_all
    if @staff.destroy
      flash[:notice] = "スタッフ完全削除しました"
      redirect_to "/admin/staffs"      
    else
      flash[:alert] = "スタッフ削除できませんでした"
      redirect_back(fallback_location: root_path)      
    end
  end
  
  
  private 
    def staff_params
      params.require(:staff).permit(:name, :name_kanji, :user_id, staff_machine_relations_attributes: [:machine])
    end

    def staff_info_params
      params.require(:staff).permit(:name, :name_kanji, :active_flag)
    end
end

class UsersController < ApplicationController
  
  before_action :admin_user_login, only: [:index]
  before_action :user_login, only: [:show, :edit, :update]
  
  layout 'main/main'
  def index
    #ViewのFormで取得したパラメータをモデルに渡す
    logger.debug("============================== user[search] = #{params[:search]} ")
    @users = User.search(params[:search]).where.not(id: 0).order(user_type: :asc).order(name: :DESC)
    logger.debug("============================== 普通のuser_controller の　users index ")
    # @users = User.where.not(id: 0).order(name: :DESC)
    @user_count = User.all.count
    logger.debug("==============================  @user_count = #{@user_count} ")
    @user_types = {}
    UserType.all.each do |user_type|
      @user_types[user_type.type_name] = user_type.id
    end
    
    if params[:search]
      @user = params[:search][:name]
      @user_type = params[:search][:user_type]
    end    

  end

  def show
    @user = User.find(params[:id])
    # showにアクセスがあった時はeditに飛ばす
    redirect_to edit_user_path(@user)
  end
  
  def edit
    @user = User.find(params[:id])
  end
  
  def update
    @user = User.find_by(id: params[:id])
    if @user.update(update_params)
      flash[:notice]  = "アカウント内容を更新しました。"
      if admin_user?
        redirect_to users_path
      else
        if @user.registration_status
          redirect_to edit_user_path(current_user)
        else
          SignupMailer.send_when_signup(@user).deliver
          SignupMailer.send_when_signup_admin(@user).deliver  
          redirect_to registration_thanks_path
        end
      end
    else 
      flash[:notice]  = "更新できませんでした"
      render "users/edit"     
    end
  end
  
  def destroy
    @user = User.find_by(id: params[:id])
    logger.debug("=============================== destroy = #{@user.name}")
    if @user.present?
      name = @user.name
      @user.destroy
      flash[:notice] = "#{name}様を削除しました"
    else
      flash[:alert] = "#{name}様を削除できませんでした"
    end
    redirect_to users_path
  end
  
  
  def backup_users
     @users = User.all
     UserBackup.delete_all
     @users.each do |user|
       @backup_user = UserBackup.new
       
       @backup_user.id = user.id
       @backup_user.email = user.email
       @backup_user.encrypted_password = user.encrypted_password
       @backup_user.reset_password_token = user.reset_password_token
       @backup_user.reset_password_sent_at = user.reset_password_sent_at
       @backup_user.remember_created_at = user.remember_created_at
       @backup_user.confirmation_token = user.confirmation_token
       @backup_user.confirmed_at = user.confirmed_at
       @backup_user.confirmation_sent_at = user.confirmation_sent_at
       @backup_user.unconfirmed_email = user.unconfirmed_email
       @backup_user.name_kana = user.name_kana
       @backup_user.name = user.name
       @backup_user.tel = user.tel
       @backup_user.birthday = user.birthday
       @backup_user.introducer = user.introducer
       @backup_user.gender = user.gender
       @backup_user.remarks = user.remarks
       @backup_user.membership_number = user.membership_number
       @backup_user.user_type = user.user_type
       @backup_user.abo = user.abo
       @backup_user.created_at = user.created_at
       @backup_user.updated_at = user.updated_at
       
       @backup_user.save
       
     end
     
     logger.debug("------------- original users count = #{@users.count}")
     logger.debug("------------- backup users count = #{UserBackup.all.count}")
     flash[:notice] = "#{UserBackup.all.count-1}件のバックアップをしました。"
     redirect_to users_path
  end
  
# private method -----------------------------
  
  private
        
      def update_params
          params.require(:user).permit(:password, :email, :name, :name_kana, :tel, :birthday, :introducer, :gender, :remarks, :user_type, :abo)
      end
      
      def admin_user_login
        if !user_signed_in? || User.find_by(id: current_user.id).user_type != "1"
          flash[:alert] = "アクセス権限がありません"
          redirect_to new_user_session_path
        end
      end
      
      def user_login
        if !user_signed_in?
          flash[:alert] = "ログインしてください"
          redirect_to new_user_session_path
        end
      end
  
  
end

# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  before_action :configure_sign_up_params, only: [:create]
  before_action :configure_account_update_params, only: [:update]
  
  layout 'main/main'

  # GET /resource/sign_up
  # def new
  #   super
  # end

  # POST /resource
  def create
    # logger.debug("====================== create")
    super
  end

  # GET /resource/edit
  def edit
    logger.debug("====================== edit")
    super
  end

  # PUT /resource
  def update
    logger.debug("====================== update action 通過")
      @user = current_user
      # if @user.email == ENV['USER_EMAIL']
      if @user.user_type == nil
        @user.user_type = "0"
      end
      
      if current_user.valid_password?(params[:user][:current_password])
        logger.debug("-------------------- user.valid_password?(params[:user][:password]) = true")
        super do
          # logger.debug("================== update resource_updated  = #{user_updated}")
          if params[:user][:birthday].present? || 
             params[:user][:name_kana].present? || 
             params[:user][:tel].present? ||
             params[:user][:introducer].present? || 
             params[:user][:gender].present? ||
             params[:user][:email].present? ||
             params[:user][:name].present?
            # flash[:alert] = "更新できません"
          else
            @new_user = User.find(@user.id)
            logger.debug("------------------ registrations/update name = #{@new_user.name}")
            SignupMailer.send_when_signup(@new_user).deliver
            SignupMailer.send_when_signup_admin(@new_user).deliver          
          end

        end
      else
        logger.debug("-------------------- user.valid_password?(params[:user][:password]) = false")
        redirect_to edit_user_registration_path
      end
    # end
  end

  # DELETE /resource
  # def destroy
  #   super
  # end

  # GET /resource/cancel
  # Forces the session data which is usually expired after sign
  # in to be expired now. This is useful if the user wants to
  # cancel oauth signing in/up in the middle of the process,
  # removing all OAuth session data.
  # def cancel
  #   super
  # end

  protected

    # If you have extra params to permit, append them to the sanitizer.
    def configure_sign_up_params
      devise_parameter_sanitizer.permit(:sign_up, keys: [:name])
    end
  
    # If you have extra params to permit, append them to the sanitizer.
    #
    # user_type は管理者のときだけ permit する。
    # account_update の対象は current_user 自身なので、ID を差し替えるまでもなく
    # 自分の登録情報編集から user_type: "1" を送るだけで管理者に昇格できた。
    # UsersController#update_params と同じ穴の別経路なので、判定も書き方も揃える。
    # 片方だけ直すと経路が残る。
    #
    # remarks は会員本人が登録時に書く備考のため対象外（現状維持）。
    def configure_account_update_params
      keys = [:current_password, :email, :name, :name_kana, :tel, :birthday, :introducer, :gender, :remarks, :abo, :membership_number]
      keys << :user_type if current_user&.user_type == "1"
      devise_parameter_sanitizer.permit(:account_update, keys: keys)
    end
  
    # The path used after sign up.
    def after_sign_up_path_for(resource)
      # edit_user_registration_path
      edit_user_path(resource)
    end
  
    # The path used after sign up for inactive accounts.
    def after_inactive_sign_up_path_for(resource)
      edit_user_registration_path
    end
    
    def after_update_path_for(resource)
        # "/reserves/h/index"
        registration_thanks_path
    end
end

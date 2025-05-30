# frozen_string_literal: true

class Users::PasswordsController < Devise::PasswordsController
  
  layout 'main/main'
  # GET /resource/password/new
  def new
    super
  end

  # POST /resource/password
  def create
    logger.debug("password controller create")
    super do |resource|
      if resource.errors.any?
        # "ユーザ は保存されませんでした" というメッセージが含まれている場合、それを削除
        # resource.errors.delete(:base)
        logger.debug("Password reset errors: #{resource.errors.full_messages}")
      end
    end
  end

  # GET /resource/password/edit?reset_password_token=abcdef
  # def edit
  #   super
  # end

  # PUT /resource/password
  # def update
  #   super
  # end

  # protected

  # def after_resetting_password_path_for(resource)
  #   super(resource)
  # end

  # The path used after sending reset password instructions
  # def after_sending_reset_password_instructions_path_for(resource_name)
  #   super(resource_name)
  # end
end

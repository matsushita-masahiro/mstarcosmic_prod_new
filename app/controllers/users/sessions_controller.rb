# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  layout 'main/main'
  respond_to :html, :turbo_stream

  # GET /resource/sign_in
  def new
    respond_to do |format|
      format.html { super }
      format.turbo_stream { render :new }
    end
  end

  # POST /resource/sign_in
  def create
    logger.debug("session create 通過")
    respond_to do |format|
      format.html { super }
      format.turbo_stream { head :ok }  # ← 成功したよ、的なレスポンスだけ返す（またはredirectでも可）
    end
  end


  # DELETE /resource/sign_out
  def destroy
    respond_to do |format|
      format.html { super }
      format.turbo_stream { redirect_to after_sign_out_path_for(resource_name), status: :see_other }
    end
  end

  def after_sign_out_path_for(resource_or_scope)
    root_path
  end

  def after_sign_in_path_for(resource_or_scope)
    root_path
  end
end

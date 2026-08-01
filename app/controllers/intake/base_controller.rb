module Intake
  # 患者が iPad で触る画面の基底クラス。
  #
  # ApplicationController を継承しない。devise のヘルパも before_action も
  # 継承させないことで、「管理機能へ辿り着く経路がコード上存在しない」状態を作る。
  # allow_browser も意図的に継承しない（患者端末で予期せぬブロックを避けるため）。
  class BaseController < ActionController::Base
    layout "intake"

    protect_from_forgery with: :exception
    before_action :authenticate_intake_session!
    before_action :set_no_store

    helper_method :current_patient, :intake_session

    # devise ヘルパを誤って呼んでも必ず nil / false になるよう明示的に潰す
    def current_user = nil
    def user_signed_in? = false

    private

    def authenticate_intake_session!
      @intake_session = IntakeSession.authenticate(session[:intake_token])
      return if @intake_session

      reset_session
      redirect_to intake_expired_path
    end

    def intake_session = @intake_session
    def current_patient = @intake_session.user

    def set_no_store
      response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, private"
      response.headers["Pragma"] = "no-cache"
    end
  end
end

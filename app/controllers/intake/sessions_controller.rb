module Intake
  # トークンの受け取りと終了画面。認証前に通るため BaseController を継承しない。
  class SessionsController < ActionController::Base
    layout "intake"
    before_action :set_no_store

    # GET /s/:token  ← スタッフが発行した QR / URL の入口
    def show
      record = IntakeSession.authenticate(params[:token])
      return redirect_to intake_expired_path unless record

      # セッション固定攻撃対策 + URL からトークンを消す（履歴・肩越しの覗き見対策）
      reset_session
      session[:intake_token] = params[:token]

      redirect_to new_intake_consent_path
    end

    def expired
      render :expired, status: :gone
    end

    # 提出完了。ここで止まり、スタッフが操作するまで先へ進めない。
    def thanks
      @signer_name = session[:completed_signer_name]
      reset_session
    end

    private

    def set_no_store
      response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, private"
    end
  end
end

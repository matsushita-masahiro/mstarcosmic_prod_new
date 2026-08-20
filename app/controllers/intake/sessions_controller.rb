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

      redirect_to entry_path_for(record.user)
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

    # QR を開いたあとの行き先。
    #
    # 署名済みなら同意書を飛ばす。ここで無条件に同意書へ送っていたため、
    # 中断して開き直した患者・別端末で開いた患者が再署名させられ、
    # 同意書レコードが増えていた（本番で発生。同一来店・同一署名者で
    # 30秒差と7分差の重複を確認）。
    #
    # 「もう署名した」かどうかを session[:intake_token] では判定できない。
    # あれは Cookie セッションで端末ごとに別物なので、別端末で開けば
    # 必ず未署名に見える。署名の有無はサーバ側の事実（Consent）で見る。
    #
    # 問診票側にも同じガードがあるが（questionnaires#show）、入口が
    # 問診票を経由しないため働く機会が無かった。
    #
    # 【将来の分岐点】訂正機能で intake_sessions.purpose を入れるときは、
    # 振り分けをここに足すこと。別の場所に分岐を作らないこと。
    #   purpose: initial かつ未署名   → 同意書
    #   purpose: initial かつ署名済み → 問診票
    #   purpose: revision            → 訂正画面
    def entry_path_for(patient)
      Consent.current_for?(patient) ? intake_questionnaire_path : new_intake_consent_path
    end

    def set_no_store
      response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, private"
    end
  end
end

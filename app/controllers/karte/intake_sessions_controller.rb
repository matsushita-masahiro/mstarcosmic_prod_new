module Karte
  # iPad で患者に記入してもらうための入場トークンを発行する。
  #
  # 【raw_token の扱い】
  # IntakeSession は token のダイジェストのみを DB に保存するため、
  # 平文トークンを取得できるのは issue! の直後だけである。
  # Turbo Drive はフォーム送信への非リダイレクト応答を描画しないため
  # create で直接ビューを返せない。そこで raw_token をセッションに一時的に置き、
  # リダイレクト先の show で取り出して即削除する。
  #
  # セッションに置く時間は1リクエスト分に限定される。以下を守ること:
  #   - 読み出し時は必ず session.delete で取り出す（残さない）
  #   - ログに出さない（params ではなく session 経由にしているのはこのため）
  #   - 再表示が必要な場合は再発行する（旧トークンは issue! 側で自動失効する）
  class IntakeSessionsController < BaseController
    SESSION_KEY = :pending_intake_token

    def create
      user = User.find(params[:user_id])
      intake_session = IntakeSession.issue!(
        patient: user, issuer: current_user, issuer_ip: request.remote_ip
      )

      log_access!(patient: user, action: "issue_intake_token", resource: intake_session)

      session[SESSION_KEY] = intake_session.raw_token
      redirect_to karte_intake_session_path(intake_session)
    end

    def show
      @intake_session = IntakeSession.find(params[:id])
      @user = @intake_session.user

      # 一度きり。再読み込み・戻る操作では取り出せない。
      raw_token = session.delete(SESSION_KEY)

      if raw_token.blank?
        return redirect_to karte_user_path(@user),
                           alert: "QRコードの表示期限が切れました。もう一度発行してください。"
      end

      unless @intake_session.active?
        return redirect_to karte_user_path(@user),
                           alert: "この入力用リンクは既に無効です。もう一度発行してください。"
      end

      @entry_url = intake_entry_url(token: raw_token, host: intake_host)
    end

    def destroy
      intake_session = IntakeSession.find(params[:id])
      intake_session.revoke!
      session.delete(SESSION_KEY)
      redirect_to karte_user_path(intake_session.user),
                  notice: "入力用リンクを無効化しました"
    end

    private

    def intake_host
      ENV.fetch("INTAKE_HOST") do
        Rails.env.production? ? "intake.#{request.domain}" : "intake.localhost:3000"
      end
    end
  end
end

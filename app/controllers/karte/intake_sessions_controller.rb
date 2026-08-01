module Karte
  # iPad で患者に記入してもらうための入場トークンを発行する。
  class IntakeSessionsController < BaseController
    def create
      @user = User.find(params[:user_id])
      @intake_session = IntakeSession.issue!(
        patient: @user, issuer: current_user, issuer_ip: request.remote_ip
      )

      log_access!(patient: @user, action: "issue_intake_token", resource: @intake_session)

      # raw_token を取得できるのはこの瞬間だけ（DB にはダイジェストのみ保存）
      @entry_url = intake_entry_url(token: @intake_session.raw_token, host: intake_host)
    end

    def destroy
      @intake_session = IntakeSession.find(params[:id])
      @intake_session.revoke!
      redirect_to karte_user_path(@intake_session.user),
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

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

    # 新規記入と訂正で発行するトークンが違うが、QR の出し方
    # （raw_token をセッションに1回だけ置いて show で消す）は同じなので
    # 別コントローラにせず、ここで分岐する。
    # 分けると、この一度きりの受け渡しをもう1組書くことになり、
    # 片方だけ直して食い違う。
    def create
      user = User.find(params[:user_id])
      target = revision_target(user)

      intake_session =
        if target
          IntakeSession.issue_revision!(
            patient: user, issuer: current_user, target: target, issuer_ip: request.remote_ip
          )
        else
          IntakeSession.issue!(
            patient: user, issuer: current_user, issuer_ip: request.remote_ip
          )
        end

      log_access!(patient: user,
                  action: target ? "issue_revision_token" : "issue_intake_token",
                  resource: intake_session)

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

      # url_helper は routes の subdomain 制約を満たすようホスト名を組み直すため、
      # host: を渡しても intake-staging が intake に書き換えられてしまう。
      # ここでは制約の影響を受けない文字列組み立てにする。
      @entry_url = "#{request.protocol}#{intake_host}/s/#{raw_token}"
    end

    def destroy
      intake_session = IntakeSession.find(params[:id])
      intake_session.revoke!
      session.delete(SESSION_KEY)
      redirect_to karte_user_path(intake_session.user),
                  notice: "入力用リンクを無効化しました"
    end

    private

    # 訂正の対象。questionnaire_id が無ければ新規記入。
    #
    # 患者の問診票からしか引かない。他人の問診票 ID を渡されても
    # 見つからず、その患者の記録に別人の版がぶら下がることを防ぐ。
    #
    # 下書きは対象にしない。提出していない版に訂正版を作ると、
    # 何を直したのかが記録として意味を持たない。
    def revision_target(user)
      id = params[:questionnaire_id]
      return nil if id.blank?

      user.medical_questionnaires.finalized.find(id)
    end

    def intake_host
      ENV.fetch("INTAKE_HOST") do
        Rails.env.production? ? "intake.#{request.domain}" : "intake.localhost:3000"
      end
    end
  end
end

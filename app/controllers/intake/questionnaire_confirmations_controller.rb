module Intake
  # 記入内容の確認と署名。
  #
  # 【なぜ確認画面を挟むか】
  # 「読んで、確認して、署名した」という流れを画面で分けるため。
  # 記入の末尾に署名欄を置くと、下まで書いた勢いで署名することになり、
  # 何に署名したのかが記録として弱い。
  #
  # 【なぜ下書きとして保存してから署名させるか（案A）】
  # 自動保存が30秒ごとに下書きを作っているので、画面に持ち回る方式にしても
  # 「署名なしのレコード」は結局サーバに存在する。持ち回る利点が無い。
  # 加えて、確定を必ず submit! に通せる。latest_questionnaire（SQL 側）と
  # latest_finalized_questionnaire（Ruby 側）は nil の畳み方が違うため、
  # submit! を経由しない確定の経路ができると両者が食い違う。
  #
  # 【署名まわりは同意書（Intake::ConsentsController）と同じ形にしている】
  # signature_pad_controller.js が送る payload、KarteAttachment への渡し方、
  # 二重送信を患者にエラーで見せない扱い、いずれも同意書に倣っている。
  class QuestionnaireConfirmationsController < BaseController
    include QuestionnaireDraft

    # 患者に選ばせる署名者の区分。
    # モデルの enum は Consent に合わせて other も持つが、画面には出さない
    # （患者に3択を出しても「代理人」と「その他」の区別がつかない）。
    SIGNER_RELATIONS = %w[self_signed guardian].freeze

    def show
      @questionnaire = draft_scope.first

      # 下書きが無い＝まだ送信していない、または確定済み。記入画面へ返す。
      # 記入画面側が、確定済みなら入口へ送り返す判断を持っている。
      return redirect_to intake_questionnaire_path if @questionnaire.nil?

      @questions = MedicalQuestionnaireForm::QUESTIONS
      @entries = @questionnaire.handwriting_entries.index_by(&:question_key)
      @body_marks = @questionnaire.body_marks.to_a

      # 訂正でなければ present? が false になり、画面には何も出ない。
      @diff = QuestionnaireRevisionDiff.new(@questionnaire)

      @signer_name = default_signer_name
    end

    def create
      questionnaire = draft_scope.first

      # 二重送信・別タブからの確定。既に確定しているので完了画面へ送る。
      # 患者にエラーを見せる意味は無い（有効な署名は既にサーバにある）。
      return render json: { redirect_to: intake_thanks_path } if questionnaire.nil?

      # 同時送信で署名が上書きされるのを止める。
      # 二重に走っても、後から来たほうは status_draft? を満たさず false で返る。
      signed = false
      questionnaire.with_lock do
        signed = questionnaire.sign_and_submit!(
          intake_session: intake_session,
          signer_name: params[:signer_name].to_s.strip,
          signer_relation: signer_relation,
          strokes: parsed_strokes,
          ip_address: request.remote_ip,
          user_agent: request.user_agent&.truncate(255)
        )
      end
      return render json: { redirect_to: intake_thanks_path } unless signed

      # 画像は保存後に添付する（blob のキーに患者IDを含めるため）
      KarteAttachment.attach!(
        record: questionnaire, name: :signature_image,
        data_url: params[:signature_image],
        user_id: current_patient.id, label: "questionnaire"
      )

      questionnaire.sync_patient_gender!

      intake_session.complete!(ip: request.remote_ip, user_agent: request.user_agent)
      session[:completed_signer_name] = questionnaire.signer_name

      render json: { redirect_to: intake_thanks_path }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    private

    def signer_relation
      value = params[:signer_relation].to_s
      SIGNER_RELATIONS.include?(value) ? value : "self_signed"
    end

    # 署名者名は漢字の氏名を優先する。
    # カナは署名欄としては不自然なため、name が無い場合の代替に留める。
    # （Intake::ConsentsController と同じ扱い）
    def default_signer_name
      current_patient.name.presence || current_patient.name_kana.presence || "本人"
    end

    # 同意書側と同じ形。JSON が壊れていたら nil にして、
    # 署名が無いものとして検証に落とす（署名の代わりに空配列を入れない）。
    def parsed_strokes
      raw = params[:signature_strokes]
      return nil if raw.blank?
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end
  end
end

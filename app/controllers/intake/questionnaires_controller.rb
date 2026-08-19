module Intake
  class QuestionnairesController < BaseController
    def show
      return redirect_to new_intake_consent_path unless Consent.current_for?(current_patient)

      @questionnaire = find_or_build_draft
      @questions = MedicalQuestionnaireForm::QUESTIONS

      # users.gender があればそれを使い、無ければ問診票の冒頭で聞く
      @gender_known = current_patient.gender_known?
      @is_female = current_patient.female?
    end

    # 自動保存（30秒ごと）。送られてきたものだけを更新する。
    #
    # 【「届かない」と「届いて空」は別物】
    #   キーが届かない       … 前回から変更なし → 触らない
    #   キーが届いて中身が空 … 患者が全部消した → 消す
    #
    # autosave は前回から変わっていないものを送らない（通信量のため）。
    # 届かなかったものを「空になった」と解釈すると、患者が触っていない
    # 手書き・人体図が自動保存のたびに消える。
    # 逆に空を握りつぶすと、「消す」ボタンで全部消しても下書きに残り続ける。
    #
    # 「届かない」と「届いて空」の区別は parse_json_param が返す nil と
    # 空コレクションで表され、保存側が自分で判断する。
    # 呼び出し側に条件分岐を置かないのは、destroy_all を含む処理の門番を
    # 呼ぶ側の注意力に預けないため。
    def update
      questionnaire = find_or_build_draft

      ActiveRecord::Base.transaction do
        questionnaire.answers = parsed_answers
        questionnaire.save!

        # partial は「この内容は全欄の状態を表していない」というクライアントの申告。
        # 端末側で復元に失敗したときに付く。削除方向の解釈だけを止め、
        # 上書き（新しく書いたぶんの保存）は通常どおり行う。
        save_handwriting_entries(questionnaire, parse_json_param(:handwriting),
                                 prune: !partial_payload?)
        save_body_marks(questionnaire, parse_json_param(:body_marks))
      end

      render json: { saved_at: Time.current.iso8601 }
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def create
      questionnaire = find_or_build_draft
      questionnaire.answers = parsed_answers

      ActiveRecord::Base.transaction do
        questionnaire.save!
        save_handwriting_entries(questionnaire, parse_json_param(:handwriting))
        save_body_marks(questionnaire, parse_json_param(:body_marks))
        questionnaire.submit!(intake_session: intake_session)
        sync_gender_if_needed(questionnaire)
      end

      intake_session.complete!(ip: request.remote_ip, user_agent: request.user_agent)
      session[:completed_signer_name] = current_patient.name.presence || current_patient.name_kana

      render json: { redirect_to: intake_thanks_path }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    private

    def find_or_build_draft
      current_patient.medical_questionnaires
                     .status_draft
                     .where(intake_session: intake_session)
                     .first_or_initialize(
                       form_version: MedicalQuestionnaireForm::VERSION,
                       intake_session: intake_session
                     )
    end

    def parsed_answers
      raw = params[:answers]
      return {} if raw.blank?
      raw.is_a?(String) ? JSON.parse(raw) : raw.to_unsafe_h
    rescue JSON::ParserError
      {}
    end

    # 問診票で性別を聞いた場合、users 側が未設定なら反映する。
    # 既に値がある場合は上書きしない（患者の自己申告より既存データを優先）。
    def sync_gender_if_needed(questionnaire)
      return if current_patient.gender.present?

      answer = questionnaire.answers["q0_gender"]
      return if answer.blank?

      current_patient.update_column(:gender, answer == "female" ? "f" : "m")
    end

    # 届いた handwriting は「今この時点の全欄の状態」を表す。
    # collectHandwriting() は空欄のキーを落とすため、含まれないキーは
    # 「患者が消した欄」と読める。したがって上書きに加えて削除も行う。
    #
    # entries が nil のとき（キーが届かない／壊れた JSON）は何もしない。
    # {} が届いたときは全欄が消されたということなので、全件を消す。
    # この nil と {} の区別が「触らない」と「消す」を分けている。
    # 削除を含むため、その判断はメソッド側に閉じる（save_body_marks と揃える）。
    #
    # prune: false のときは上書きだけして削除しない。
    # 端末が復元に失敗している（画面が全欄の状態を表していない）ときに使う。
    # create は画面が確定した状態を送るので既定の true のまま。
    def save_handwriting_entries(questionnaire, entries, prune: true)
      return if entries.nil?

      entries.each do |key, data|
        next unless MedicalQuestionnaireForm.handwriting_keys.include?(key)

        entry = questionnaire.handwriting_entries.find_or_initialize_by(question_key: key)
        entry.input_mode = data["mode"] == "keyboard" ? :keyboard : :pen

        if entry.input_mode_keyboard?
          entry.transcribed_text = data["text"].to_s
          entry.strokes = []
        else
          entry.strokes = data["strokes"] || []
          entry.canvas_width  = data["width"]
          entry.canvas_height = data["height"]
        end

        entry.save!

        # 画像は保存後に添付する（blob のキーに患者IDを含めるため）
        next if entry.input_mode_keyboard?
        KarteAttachment.attach!(
          record: entry, name: :image, data_url: data["image"],
          user_id: current_patient.id, label: key
        )
      end

      return unless prune

      # 届かなかった欄は消えたものとして削除する。
      # destroy は has_one_attached の既定（dependent: :purge_later）で
      # PNG の blob も片付ける。
      questionnaire.handwriting_entries.reload
                   .reject { |entry| entries.key?(entry.question_key) }
                   .each(&:destroy)
    end

    # 人体図は「1枚の絵」で部分更新の単位が無いため、届いたときは全置換する。
    #
    # nil（キーが届かない／壊れた JSON）なら何もしない。
    # [] が届いたときは全マーカーが消されたということなので、全消しが正しい。
    #
    # marks を引数で受けるのは、destroy_all の門番を呼び出し側の確認漏れに
    # 依存させないため。以前は params から自分で読んでおり、
    # 呼ぶ側が有無を確かめ忘れると即座に全消しになる形だった。
    def save_body_marks(questionnaire, marks)
      return if marks.nil?

      questionnaire.body_marks.destroy_all
      marks.each do |m|
        x = m["x"].to_f
        y = m["y"].to_f
        next unless x.between?(0, 1) && y.between?(0, 1)

        questionnaire.body_marks.create!(
          side: m["side"] == "back" ? :back : :front,
          x: x, y: y,
          mark_type: %w[pain numbness stiffness other].include?(m["mark_type"]) ? m["mark_type"] : "pain",
          note: m["note"].presence
        )
      end
    end

    # クライアントが「この内容は全欄の状態を表していない」と申告したか。
    # 復元に失敗した端末が付けてくる。値は問わず、有無だけを見る。
    def partial_payload?
      params[:partial].present?
    end

    def parse_json_param(name)
      raw = params[name]
      return nil if raw.blank?
      raw.is_a?(String) ? JSON.parse(raw) : raw
    rescue JSON::ParserError
      nil
    end
  end
end

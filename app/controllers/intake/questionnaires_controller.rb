module Intake
  class QuestionnairesController < BaseController
    include QuestionnaireDraft

    def show
      return redirect_to new_intake_consent_path unless consent_satisfied?

      @questionnaire = find_or_build_draft
      @questions = rendered_questions

      # 記入途中の内容を端末の localStorage と同じ形で渡し、JS 側で描き直す。
      # ERB の各 input に値を埋めないのは、手書き（canvas）が結局 JS でしか
      # 描けず、二重管理になるため。復元処理を1本に保つ。
      #
      # 端末に下書きが残っていればそちらが優先される（最後の autosave が
      # 届いていない最大30秒ぶんは端末にしかない）。ここで渡すのは
      # localStorage が使えなかったときの受け皿。
      @server_draft = initial_snapshot
      @storage_key = storage_key
      @revision_target = revision_target

      # 女性専用設問（【13】妊娠）の出し分け。
      # こちらは条件を満たさなくても DOM には出力し、hidden で隠すだけ
      # （画面が全欄の状態を表していないと、autosave が削除方向に働く）。
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
        questionnaire.answers = answers_to_save
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

    # 記入内容をひととおり保存して、確認画面へ送る。
    #
    # ここでは確定しない。submit! が走るのは確認画面で署名したときだけ
    # （QuestionnaireConfirmationsController#create）。
    # 「読んで、確認して、署名した」という順序を画面で分けるため、
    # 記入の末尾に署名欄を置く形にはしていない。
    #
    # 下書きのまま残すので、確認画面から戻って書き直せる。
    # 途中で離脱してもこの時点の内容は残る（署名直前でやめても書き直しにならない）。
    #
    # トークンの失効（intake_session.complete!）と性別の反映も確定側へ移した。
    # ここで失効させると、確認画面から記入画面へ戻れなくなる。
    def create
      questionnaire = find_or_build_draft
      questionnaire.answers = answers_to_save

      ActiveRecord::Base.transaction do
        questionnaire.save!
        save_handwriting_entries(questionnaire, parse_json_param(:handwriting))
        save_body_marks(questionnaire, parse_json_param(:body_marks))
      end

      render json: { redirect_to: intake_questionnaire_confirmation_path }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    private

    # 訂正のときは、この回の下書きに前版への参照を持たせる。
    # revision（版番号）は前版から自動で継がれる（MedicalQuestionnaire 側）。
    # 初回記入では revision_target が nil なので従来と同じ。
    def find_or_build_draft
      draft_scope.first_or_initialize(
        form_version: MedicalQuestionnaireForm::VERSION,
        intake_session: intake_session,
        previous_version: revision_target
      )
    end

    # 訂正の対象。初回記入では nil。
    def revision_target
      return nil unless intake_session.purpose_revision?

      intake_session.target_questionnaire
    end

    # 画面を開いたときに描く内容。
    #
    # 訂正では前版を初期値にする。ただし、この回の下書きが既にあるなら
    # そちらが新しい（訂正を書きかけて開き直した場合）。
    # persisted? で「初めて開いた」と「続きから」を分ける。
    def initial_snapshot
      return @questionnaire.draft_snapshot unless revision_target
      return @questionnaire.draft_snapshot if @questionnaire.persisted?

      # 前版の draft_snapshot は strokes だけを返し image を含まない（A-1）。
      # そのため前版の PNG（blob）には一切触れない。ここで image まで渡すと、
      # 訂正版の送信時に同じ blob を掴んで前版の画像ごと差し替えかねない。
      revision_target.draft_snapshot
    end

    # 端末に下書きを残すときのキー。
    #
    # 訂正では初回記入と別のキーにする。既定のキーは患者ごと
    # （intake_draft_<患者ID>）で来店ごとではないため、初回記入時の
    # 書きかけが端末に残っている。同じキーを使うと、localStorage 優先の
    # 復元がそれを拾い、前版ではなく初回の書きかけが画面に出る。
    #
    # キーを分けることで、優先順位（端末 → サーバ）の仕組みを変えずに
    # 「訂正では前版が出る」を満たせる。初回の下書きも壊さない。
    def storage_key
      return "intake_draft_#{current_patient.id}" unless revision_target

      "intake_revision_#{revision_target.id}"
    end

    # 同意書を通す必要があるか。
    #
    # 訂正では通さない。「前版があるなら署名済み」は成り立たない
    # （同意書を改訂して publish すると current が切り替わり、
    # 過去に署名した患者も全員が未署名扱いになる）。
    # そこで訂正でも Consent.current_for? を見ると、過去の誤記を直すために
    # 新しい同意書へ署名させることになり、署名するまで記録が誤ったまま残る。
    #
    # 訂正は過去の記録を正すもので、新しい施術の同意とは別の話。
    # 新しい同意書への署名は、次の来店（purpose: initial）で求められる。
    def consent_satisfied?
      intake_session.purpose_revision? || Consent.current_for?(current_patient)
    end

    # 画面に出す設問。
    #
    # ask_when_unknown を持つ設問は、その情報が既に分かっている患者には
    # 出さない（性別なら users.gender が入っている人）。
    # female_only と違って hidden ですらなく、DOM に出力そのものをしない。
    #
    # 出す・出さないの判断はこの1か所だけに置く。ビューにも同じ条件を
    # 書くと、訂正の持ち越し（answers_to_save）が見ている条件と
    # 片方だけ変わって食い違い、回答が静かに消える。
    def rendered_questions
      MedicalQuestionnaireForm::QUESTIONS.reject { |q| skipped_question?(q) }
    end

    # 出力しない設問のキー。訂正で前版から持ち越す対象になる。
    def skipped_question_keys
      MedicalQuestionnaireForm::QUESTIONS.select { |q| skipped_question?(q) }
                                         .map { |q| q[:key] }
    end

    def skipped_question?(question)
      case question[:ask_when_unknown]
      when :gender then current_patient.gender_known?
      else false
      end
    end

    # 保存する回答。
    #
    # 訂正では、画面に出さなかった設問の回答を前版から補う。
    # 出力していない設問は collectAnswers() が拾いようがないため、
    # 届いた回答をそのまま入れると、答えていたはずの項目が
    # 「未回答」になって消える（性別がこれにあたる）。
    #
    # 条件付き表示（[hidden]）の設問はこの対象ではない。あちらは DOM に
    # 出力されていて、患者が条件を外したときはクライアントが値を消す。
    # 「出力しなかった」と「隠しただけ」を分けているのがこの方式の要で、
    # 前者だけを補うから、患者が消したはずの回答が復活しない。
    #
    # 届いた回答が優先。前版の値は、画面に無かったぶんの穴埋めに過ぎない。
    # 初回記入では revision_target が nil なので何も補わない。
    def answers_to_save
      carried_over_answers.merge(parsed_answers)
    end

    def carried_over_answers
      return {} unless revision_target

      (revision_target.answers || {}).slice(*skipped_question_keys)
    end

    def parsed_answers
      raw = params[:answers]
      return {} if raw.blank?
      raw.is_a?(String) ? JSON.parse(raw) : raw.to_unsafe_h
    rescue JSON::ParserError
      {}
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

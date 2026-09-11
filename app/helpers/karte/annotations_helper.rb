module Karte
  # スタッフ追記の表示を組み立てる。
  #
  # 【重要】このヘルパーが返すものは患者に見せない。呼ぶのは
  # app/views/karte/ の下だけにすること。患者向けの確認画面は
  # karte/users/_answer を直接描いており（intake/questionnaire_confirmations/
  # show.html.erb）、_answer に追記を混ぜると患者の画面に出る。
  # そのため追記は _answer ではなく karte 専用のラッパー
  # （karte/users/_annotated_answer）側に置いている。
  module AnnotationsHelper
    # 設問1件が抱えるキーの一覧。
    # 追記は設問ごとに付くが、付随項目（detail）・サブ項目（subs）・
    # その他欄（other）にも付きうるので、親の設問にまとめて出す。
    # ここで拾い漏らすと、その追記はどこにも表示されない。
    def annotation_keys_for(question)
      [ question[:key],
        question.dig(:detail, :key),
        question.dig(:other, :key),
        *Array(question[:subs]).map { |sub| sub[:key] } ].compact
    end

    # 設問1件ぶんの追記を、書かれた順に集める。
    def annotations_for_question(annotations, question)
      annotation_keys_for(question)
        .flat_map { |key| annotations[key] || [] }
        .sort_by { |a| [ a.created_at, a.id ] }
    end

    # そのキーを抱えている最上位の設問。追記は親の設問にまとめて出すため、
    # サブ項目のキーからでも親を引けるようにしておく。
    def annotation_top_level_question(question_key)
      MedicalQuestionnaireForm::QUESTIONS.find do |question|
        annotation_keys_for(question).include?(question_key.to_s)
      end
    end

    # 追記を差し込む入れ物の id。
    # Turbo Stream の append 先もこれで引くので、表示側と作成側で
    # 同じ規則から組み立てる（片方だけ変えると追記が画面に出なくなる）。
    def annotation_container_id(questionnaire, question_key)
      top = annotation_top_level_question(question_key)

      "annotations-#{questionnaire.id}-#{top ? top[:key] : question_key}"
    end

    # 追記ボタンに添える設問の名前。
    #
    # ボタンだけを置くと、直前の設問のものか直後の設問のものかが読めない。
    # 追記は消せないので、押し間違いは訂正の追記を足すしかない。
    # 設問番号があれば必ず付ける（画面の見出しと同じ手がかりになる）。
    def annotation_question_caption(question)
      label = question[:label].to_s
      label = "【#{question[:no]}】#{label}" if question[:no]

      truncate(label, length: 28)
    end

    # 追記に添える見出し。
    #
    # 色だけに意味を持たせない。印刷したときや色覚特性のある方が見たときに
    # 「スタッフが書いたもの」という情報が落ちないよう、必ず文言で示す。
    def annotation_heading(annotation, questionnaire)
      parts = [ "スタッフ追記：#{annotation.staff.name}",
                l(annotation.created_at, format: :short) ]

      # 表示中の版とは別の版に付いた追記は、どの版に書かれたかを明示する。
      # 出どころを書かないと、患者が訂正した内容への追記なのか
      # 訂正前への追記なのかが読めない。
      if annotation.medical_questionnaire_id != questionnaire.id
        parts << "（第#{annotation.medical_questionnaire.revision}版への追記）"
      end

      parts.join("　")
    end

    # 親の設問と違うキーに付いた追記では、どの項目への追記かを出す。
    def annotation_sub_label(annotation, question)
      return nil if annotation.question_key == question[:key]

      MedicalQuestionnaireForm.find(annotation.question_key)&.dig(:label)
    end
  end
end

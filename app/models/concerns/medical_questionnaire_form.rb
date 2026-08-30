# 問診票の設問定義。
#
# 設問は改訂されるため、コードではなくこの定義を版ごとに持つ。
# answers（jsonb）のキーはここで定義した key と一致させること。
#
# 【重要】禁忌判定に使うキーと値は
# MedicalQuestionnaire#promote_flags_from_answers と対応している。
#   q10_pacemaker → has_pacemaker（"yes" で真）
#   q13_pregnant  → is_pregnant("yes") / pregnancy_unknown("unknown")
# キー名または value を変える場合は必ず両方を直すこと。
#
# 選択肢は { value:, label: } で表示と値を分離する。
# 表示ラベルをそのまま値にすると、文言を変えただけで判定が壊れるため。
# :checkboxes は値そのものに意味がある（病名など）ため文字列のまま扱う。
#
# type:
#   :boolean      いいえ / はい
#   :radio        単一選択
#   :select       プルダウン（選択肢が多い場合）
#   :checkboxes   複数選択
#   :text         1行テキスト
#   :handwriting  ペン or キーボード切替の自由記述
#   :composite    サブ項目を持つ
#
# female_only: true を指定した設問は、女性と判定された場合のみ表示する。
#
# ask_unless: 既に分かっていることは聞かない設問。値は患者（User）の述語名で、
# それが真なら出力しない（:gender_known? なら users.gender が判別できる
# 患者には性別を聞かない）。設問ごとに述語を差し替えられる。
#
# 区分名ではなく述語名そのものを書くのは、何を見て出し分けているかを
# 設問定義だけで読めるようにするため。以前は :gender という区分名を持ち、
# 対応する述語は Intake::QuestionnairesController の case 式が握っていた。
# その形だと設問を足すたびにコントローラ側の分岐も足すことになり、
# 足し忘れると「聞かないはずの設問」が全員に出る。
#
# 述語は User に生えていること。綴りを間違えると記入画面が 500 になる。
# 定義側で気づけるよう medical_questionnaire_form_test が全件を確かめている。
#
# 【female_only との違い。混同すると回答が消える】
#   female_only  条件を満たさなくても DOM には出力され、hidden で隠れるだけ。
#                画面は全欄の状態を表しているので、訂正しても回答は失われない。
#   ask_unless   条件を満たすと、そもそも出力しない。画面に無い＝収集されない
#                ので、訂正では前版から持ち越さないと回答が消える
#                （Intake::QuestionnairesController#answers_to_save）。
#
# つまり female_only は「表示するかどうか」、ask_unless は
# 「出力するかどうか」。性質が違うので同じ属性に寄せないこと。
module MedicalQuestionnaireForm
  VERSION = "2026-08-03".freeze

  # 性別の設問キー。users.gender への反映
  # （MedicalQuestionnaire#sync_patient_gender!）が同じキーを見るため、
  # 両者が直書きで食い違わないよう定数にしている。
  GENDER_KEY = "q0_gender".freeze

  # 血液型の設問キー。users.blood_type への反映
  # （MedicalQuestionnaire#sync_patient_blood_type!）が同じキーを見るため、
  # 性別と同じく定数にしている。
  BLOOD_TYPE_KEY = "q0_blood_type".freeze

  YES_NO = [
    { value: "no",  label: "いいえ" },
    { value: "yes", label: "はい" }
  ].freeze

  QUESTIONS = [
    # 性別。users.gender が未設定の患者にだけ聞く（ask_unless）。
    #
    # 設問番号を持たせていない。既存は 1〜19 で、ぶつからない番号は 0 になるが
    # 「【0】」と画面に出るのは不自然なため。番号の無い設問は記入画面・
    # 確認画面・カルテ・差分のいずれもラベルだけを出す。
    #
    # value は "female" / "male"。sync_patient_gender! が users.gender の
    # "f" / "m" へ写しており、過去の回答もこの値で保存されている。
    {
      key: GENDER_KEY, type: :radio,
      label: "性別",
      required: true,
      ask_unless: :gender_known?,
      options: [
        { value: "female", label: "女性" },
        { value: "male",   label: "男性" }
      ]
    },
    # 血液型。users.blood_type が未設定の患者にだけ聞く（ask_unless）。
    #
    # 性別と同じく設問番号を持たない。既存は【1】〜【19】で連番になっており、
    # 途中に差し込むと以降の番号がすべてずれる。患者が紙で見慣れた番号でもある。
    #
    # 値は "a" / "b" / "o" / "ab" / "unknown" が users.blood_type へそのまま入る
    # （sync_patient_blood_type!）。gender のような変換層は持たない。
    # gender が "female" → "f" と写しているのは users.gender が問診票より古く
    # 語彙が違うためで、血液型は今回の新設なのでズレようが無い。
    #
    # 「不明」を選択肢に置くのは、答えられない患者を未回答のまま通すと
    # 次の来店でまた同じことを聞くことになるため。
    # NULL は「まだ訊いていない」、"unknown" は「訊いたが分からない」で別物。
    # ラベルはヘッダーの表示（UserKarte::BLOOD_TYPE_LABELS）と同じ文言にしてある。
    # 確認画面とヘッダーで呼び名が違うと、同じ回答が別物に見える。
    #
    # Rh は訊かない。施術の判断に使っておらず、訊く項目を増やすほど
    # 記入が重くなる。必要になったら別の設問として足すこと
    # （この設問の value に "a+" などを混ぜると過去の回答と食い違う）。
    {
      key: BLOOD_TYPE_KEY, type: :radio,
      label: "血液型",
      required: true,
      ask_unless: :blood_type_recorded?,
      options: [
        { value: "a",       label: "A型" },
        { value: "b",       label: "B型" },
        { value: "o",       label: "O型" },
        { value: "ab",      label: "AB型" },
        { value: "unknown", label: "不明" }
      ]
    },
    {
      no: 1, key: "q1_purpose", type: :handwriting,
      label: "現在のお身体の状況や来店目的を教えてください"
    },
    {
      no: 2, key: "q2_under_treatment", type: :boolean,
      label: "現在治療中の病気はありますか？",
      detail: { key: "q2_disease_name", label: "病名", type: :handwriting,
                show_when: { key: "q2_under_treatment", value: "yes" } }
    },
    {
      no: 3, key: "q3_history", type: :handwriting,
      label: "既往歴（病歴）・怪我・手術歴があったら教えてください"
    },
    {
      no: 4, key: "q4_medication", type: :boolean,
      label: "普段、飲んでいるお薬はありますか？　たまに飲むものも教えてください。",
      detail: { key: "q4_medicine_name", label: "薬名", type: :handwriting,
                show_when: { key: "q4_medication", value: "yes" } }
    },
    {
      no: 5, key: "q5_occupation", type: :handwriting,
      label: "お仕事の職種・内容を教えてください"
    },
    {
      no: 6, key: "q6_family_history", type: :checkboxes,
      label: "ご家族の中に下記の病気にかかった事がある方はいらっしゃいますか？（自分から見て三親等）",
      options: %w[糖尿病 心臓病 高血圧 喘息 肝臓病 腎臓病 癌 脳梗塞 心筋梗塞],
      other: { key: "q6_other", label: "その他の難病指定されたもの" }
    },
    {
      no: 7, key: "q7_marital_status", type: :radio,
      label: "婚姻状況",
      options: [
        { value: "single",  label: "未婚" },
        { value: "married", label: "既婚" }
      ]
    },
    {
      no: 8, key: "q8_smoking", type: :radio,
      label: "喫煙しますか？",
      options: [
        { value: "no",   label: "吸わない" },
        { value: "yes",  label: "吸う" },
        { value: "past", label: "以前吸っていた" }
      ],
      subs: [
        { key: "q8_per_day", label: "1日の本数", type: :select,
          show_when: { key: "q8_smoking", value: "yes" },
          options: [
            { value: "1-5",   label: "1〜5本" },
            { value: "6-10",  label: "6〜10本" },
            { value: "11-20", label: "11〜20本" },
            { value: "21+",   label: "21本以上" }
          ] },
        { key: "q8_quit_years", label: "禁煙してからの年数", type: :select,
          show_when: { key: "q8_smoking", value: "past" },
          options: [
            { value: "under1", label: "1年未満" },
            { value: "1-3",    label: "1〜3年" },
            { value: "4-10",   label: "4〜10年" },
            { value: "over10", label: "10年以上" }
          ] }
      ]
    },
    {
      no: 9, key: "q9_drinking", type: :radio,
      label: "飲酒しますか？",
      options: [
        { value: "no",        label: "飲まない" },
        { value: "sometimes", label: "ときどき" },
        { value: "daily",     label: "毎日" }
      ],
      subs: [
        { key: "q9_amount", label: "1日あたりの量（ビール中瓶換算）", type: :radio,
          show_when: { key: "q9_drinking", values: %w[sometimes daily] },
          options: [
            { value: "1",   label: "1本程度" },
            { value: "2-3", label: "2〜3本" },
            { value: "4+",  label: "4本以上" }
          ] }
      ]
    },
    {
      no: 10, key: "q10_pacemaker", type: :boolean,
      label: "身体の中に埋め込まれている医療機器（ペースメーカー）はありますか？",
      warning: "「はい」の場合、メタトロン測定は受けられません。",
      required: true,
      subs: [
        { key: "q10_other_device", label: "ペースメーカー以外の医療機器がある", type: :boolean },
        { key: "q10_device_name",  label: "機器名", type: :text,
          show_when: { key: "q10_other_device", value: "yes" } }
      ]
    },
    {
      no: 11, key: "q11_water", type: :radio,
      label: "お水は1日どのくらい飲みますか？",
      options: [
        { value: "under0.5", label: "0.5ℓ未満" },
        { value: "0.5-1",    label: "0.5〜1ℓ" },
        { value: "1-1.5",    label: "1〜1.5ℓ" },
        { value: "over1.5",  label: "1.5ℓ以上" }
      ]
    },
    {
      no: 12, key: "q12_supplement_advice", type: :boolean,
      label: "健康補助食品（サプリメント）等のアドバイスは必要ですか？",
      detail: { key: "q12_current", label: "現在摂取しているもの", type: :handwriting,
                show_when: { key: "q12_supplement_advice", value: "yes" } }
    },
    {
      no: 13, key: "q13_pregnant", type: :radio,
      label: "現在、妊娠中ですか？",
      warning: "妊娠中の方はメタトロン測定を受けられません。",
      female_only: true,
      required: true,
      options: [
        { value: "no",      label: "いいえ" },
        { value: "yes",     label: "はい" },
        { value: "unknown", label: "わからない" }
      ],
      subs: [
        { key: "q13_pregnancy_weeks", label: "妊娠週数", type: :select,
          show_when: { key: "q13_pregnant", value: "yes" },
          options: (1..42).map { |w| { value: w.to_s, label: "#{w}週" } } },
        { key: "q13_breastfeeding", label: "授乳中ですか？", type: :boolean }
      ]
    },
    {
      no: 14, key: "q14_food_advice", type: :boolean,
      label: "自分の身体にあう食品に対するアドバイスは必要ですか？"
    },
    {
      no: 15, key: "q15_other_advice", type: :boolean,
      label: "身体に関係する他のアドバイスは必要ですか？",
      detail: {
        key: "q15_items", type: :checkboxes,
        label: "ご希望の項目",
        show_when: { key: "q15_other_advice", value: "yes" },
        options: [
          "整体", "鍼灸", "インソール", "ヒプノバーシング", "妊活", "栄養指導",
          "腸活", "ソマチッド", "美容", "エステ",
          "幹細胞培養上清液（骨髄・臍帯・歯髄・脂肪）", "幹細胞",
          "Salt Nine", "Salt Nine＋", "Salt Four（育毛）"
        ]
      }
    },
    {
      no: 16, key: "q16_concerns", type: :handwriting,
      label: "現在悩んでいること、気になることなどありましたら教えてください"
    },
    {
      no: 17, key: "q17_has_additional", type: :boolean,
      label: "下記に該当する項目はありますか？",
      hint: "摘出臓器 / 抗がん剤 / 放射線 / 先進医療 / 幹細胞・エクソソーム",
      subs: [
        { key: "q17_removed_organ", label: "摘出臓器", type: :handwriting,
          show_when: { key: "q17_has_additional", value: "yes" } },
        { key: "q17_anticancer", label: "抗がん剤", type: :handwriting,
          show_when: { key: "q17_has_additional", value: "yes" } },
        { key: "q17_radiation", label: "放射線", type: :handwriting,
          show_when: { key: "q17_has_additional", value: "yes" } },
        { key: "q17_advanced", label: "先進医療", type: :handwriting,
          show_when: { key: "q17_has_additional", value: "yes" } },
        { key: "q17_exosome", label: "エクソソーム・幹細胞・骨髄幹細胞培養上清液", type: :handwriting,
          show_when: { key: "q17_has_additional", value: "yes" } },
        { key: "q17_other", label: "その他", type: :handwriting,
          show_when: { key: "q17_has_additional", value: "yes" } }
      ]
    },
    # コロナ関係は【17】の「はい」に関係なく常に聞く。
    # 全員に確認したい項目のため、【17】のサブ項目から独立させた。
    {
      no: 18, key: "q18_vaccinated", type: :boolean,
      label: "新型コロナウイルスのワクチンを接種しましたか？",
      subs: [
        { key: "q18_vaccine_count", label: "接種回数", type: :select,
          show_when: { key: "q18_vaccinated", value: "yes" },
          options: (1..7).map { |n| { value: n.to_s, label: "#{n}回" } } +
                   [{ value: "8+", label: "8回以上" }] }
      ]
    },
    {
      no: 19, key: "q19_infected", type: :boolean,
      label: "新型コロナウイルスに感染したことはありますか？",
      subs: [
        { key: "q19_infection_count", label: "感染回数", type: :select,
          show_when: { key: "q19_infected", value: "yes" },
          options: (1..5).map { |n| { value: n.to_s, label: "#{n}回" } } }
      ]
    }
  ].freeze

  # ペン or キーボード入力の対象キー
  def self.handwriting_keys
    collect_all.select { |q| q[:type] == :handwriting }.map { |q| q[:key] }
  end

  # 必須回答のキー（禁忌判定に関わるもの）
  def self.required_questions
    QUESTIONS.select { |q| q[:required] }
  end

  # 女性のみ表示する設問
  def self.female_only_keys
    QUESTIONS.select { |q| q[:female_only] }.map { |q| q[:key] }
  end

  def self.find(key)
    collect_all.find { |q| q[:key] == key.to_s }
  end

  # 表示用。value からラベルを引く。
  def self.label_for(key, value)
    q = find(key)
    return value unless q

    case q[:type]
    when :boolean
      YES_NO.find { |o| o[:value] == value }&.dig(:label) || value
    when :radio, :select
      Array(q[:options]).find { |o| o[:value] == value }&.dig(:label) || value
    else
      value
    end
  end

  # 設問・付随項目・サブ項目・その他欄をすべてフラットに集める。
  #
  # その他欄（other）も含めること。落とすと find("q6_other") が nil を返し、
  # カルテの差分に「その他の難病指定されたもの」ではなく
  # 「q6_other（現在の様式にない設問）」と出る。
  # カルテ本体は _answer.html.erb が明示的に描くので気づきにくい。
  def self.collect_all
    @collect_all ||= QUESTIONS.flat_map do |q|
      [q, q[:detail], q[:other], *Array(q[:subs])].compact
    end
  end
end

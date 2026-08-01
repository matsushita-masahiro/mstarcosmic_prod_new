# 問診票の設問定義。
#
# 設問は改訂されるため、コードではなくこの定義を版ごとに持つ。
# answers（jsonb）のキーはここで定義した key と一致させること。
# 【重要】禁忌判定に使うキー（q10_pacemaker / q13_pregnant）は
# MedicalQuestionnaire#promote_flags_from_answers と対応している。
# キー名を変える場合は必ず両方を直すこと。
module MedicalQuestionnaireForm
  VERSION = "2026-04-17".freeze

  # type:
  #   :boolean      いいえ / はい
  #   :text         1行テキスト
  #   :handwriting  ペン or キーボード切替の自由記述
  #   :checkboxes   複数選択
  #   :radio        単一選択
  #   :composite    サブ項目を持つ
  QUESTIONS = [
    {
      no: 1, key: "q1_purpose", type: :handwriting,
      label: "現在のお身体の状況や来店目的を教えてください"
    },
    {
      no: 2, key: "q2_under_treatment", type: :boolean,
      label: "現在治療中の病気はありますか？",
      detail: { key: "q2_disease_name", label: "病名", type: :handwriting, when: true }
    },
    {
      no: 3, key: "q3_history", type: :handwriting,
      label: "既往歴（病歴）・怪我・手術歴があったら教えてください"
    },
    {
      no: 4, key: "q4_medication", type: :boolean,
      label: "普段、飲んでいるお薬はありますか？　たまに飲むものも教えてください。",
      detail: { key: "q4_medicine_name", label: "薬名", type: :handwriting, when: true }
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
      label: "婚姻状況", options: %w[未婚 既婚]
    },
    {
      no: 8, key: "q8_smoking", type: :boolean,
      label: "喫煙しますか？",
      subs: [
        { key: "q8_per_day",   label: "1日の本数", type: :text, when: true },
        { key: "q8_past",      label: "過去喫煙あり（何年前？）", type: :text }
      ]
    },
    {
      no: 9, key: "q9_drinking", type: :boolean,
      label: "飲酒しますか？",
      detail: { key: "q9_amount", label: "1日あたりの量", type: :text, when: true }
    },
    {
      no: 10, key: "q10_pacemaker", type: :boolean,
      label: "身体の中に埋め込まれている医療機器（ペースメーカー）はありますか？",
      warning: "「はい」の場合、メタトロン測定は受けられません。",
      subs: [
        { key: "q10_other_device", label: "その他の医療機器がある", type: :boolean },
        { key: "q10_device_name",  label: "機器名", type: :text }
      ]
    },
    {
      no: 11, key: "q11_water", type: :boolean,
      label: "お水は飲むようにしていますか？",
      detail: { key: "q11_liters", label: "1日あたり（ℓ）", type: :text, when: true }
    },
    {
      no: 12, key: "q12_supplement_advice", type: :boolean,
      label: "健康補助食品（サプリメント）等のアドバイスは必要ですか？",
      detail: { key: "q12_current", label: "現在摂取しているもの", type: :handwriting }
    },
    {
      no: 13, key: "q13_female_only", type: :composite,
      label: "女性の方のみ回答ください",
      warning: "妊娠中の方はメタトロン測定を受けられません。",
      subs: [
        { key: "q13_pregnant", label: "現在、妊娠中ですか？", type: :radio,
          options: %w[いいえ はい 不明] },
        { key: "q13_pregnancy_weeks", label: "妊娠週数", type: :text },
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
      no: 17, key: "q17_additional", type: :composite,
      label: "下記も該当する方は記入お願い致します",
      optional: true,
      subs: [
        { key: "q17_removed_organ",  label: "摘出臓器", type: :text },
        { key: "q17_anticancer",     label: "抗がん剤", type: :text },
        { key: "q17_radiation",      label: "放射線", type: :text },
        { key: "q17_advanced",       label: "先進医療", type: :text },
        { key: "q17_exosome",        label: "エクソソーム・幹細胞・骨髄幹細胞培養上清液", type: :text },
        { key: "q17_vaccine_count",  label: "コロナワクチン接種回数", type: :text },
        { key: "q17_covid_count",    label: "コロナ感染回数", type: :text },
        { key: "q17_other",          label: "その他", type: :text }
      ]
    }
  ].freeze

  # ペン or キーボード入力の対象キー
  def self.handwriting_keys
    QUESTIONS.flat_map do |q|
      keys = []
      keys << q[:key] if q[:type] == :handwriting
      keys << q.dig(:detail, :key) if q.dig(:detail, :type) == :handwriting
      keys
    end.compact
  end

  def self.find(key)
    QUESTIONS.find { |q| q[:key] == key.to_s }
  end
end

# app/models/concerns/medical_questionnaire_flags.rb
#
# answers（jsonb）から独立カラムへの昇格を担う。
#
# 【設計方針】
# カラムに昇格させるのは「禁忌判定に使うもの」だけに限定する。
# 設問は改訂されるため、カラムを増やすほど改訂コストが上がる。
# 参照はするが判定に使わないもの（コロナワクチン接種回数など）は
# answers から読むヘルパを用意するに留める。
#
# 【重要】FLAG_CONTRACT は MedicalQuestionnaireForm の定義と対応している。
# 設問のキー名または選択肢の value を変えると静かに壊れるため、
# test/models/medical_questionnaire_flags_test.rb で契約を検証している。
# テストが落ちたら、テストではなくこちらか設問定義のどちらかを直すこと。
module MedicalQuestionnaireFlags
  extend ActiveSupport::Concern

  # カラムに昇格させるキー => その設問が取りうる value の一覧
  FLAG_CONTRACT = {
    "q10_pacemaker" => %w[no yes],
    "q13_pregnant"  => %w[no yes unknown]
  }.freeze

  # 昇格させないが、カルテ表示・集計で参照するキー
  REFERENCE_KEYS = %w[
    q17_has_additional
    q17_vaccinated q17_vaccine_count
    q17_infected q17_infection_count
  ].freeze

  # answers から安全に1件取り出す（answers が nil でも落ちない）
  def answer_for(key)
    (answers || {})[key.to_s]
  end

  # ── 参照用（カラムには持たない）────────────────
  def vaccinated?
    answer_for("q17_vaccinated") == "yes"
  end

  def vaccine_count
    answer_for("q17_vaccine_count").presence
  end

  def covid_infected?
    answer_for("q17_infected") == "yes"
  end

  def covid_infection_count
    answer_for("q17_infection_count").presence
  end

  # 【17】に何か該当があるか
  def additional_items?
    answer_for("q17_has_additional") == "yes"
  end

  # ── 昇格 ────────────────────────────────────
  #
  # 既存の before_save コールバックから呼ばれる想定。
  # コールバックの登録は MedicalQuestionnaire 側に残したまま、
  # メソッドの実体だけをこちらへ移すこと。
  def promote_flags_from_answers
    # 下書きのうちは常に現行版に追随させる（記入中に設問が改訂された場合、
    # 画面に出ているのは新しい設問のため）。提出済みは当時の版を保持する。
    if form_version.blank? || (respond_to?(:status_draft?) && status_draft?)
      self.form_version = MedicalQuestionnaireForm::VERSION
    end

    self.has_pacemaker = answer_for("q10_pacemaker") == "yes"

    case answer_for("q13_pregnant")
    when "yes"     then assign_pregnancy(pregnant: true,  unknown: false)
    when "unknown" then assign_pregnancy(pregnant: false, unknown: true)
    else                assign_pregnancy(pregnant: false, unknown: false)
    end
  end

  private

  # 男性・未回答は「妊娠していない」として扱う。
  # 【13】は female_only のため男性には表示されず、値は常に空になる。
  def assign_pregnancy(pregnant:, unknown:)
    self.is_pregnant       = pregnant
    self.pregnancy_unknown = unknown
  end
end

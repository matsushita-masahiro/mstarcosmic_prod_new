# app/models/concerns/medical_questionnaire_flags.rb
#
# answers（jsonb）から独立カラムへの昇格を担う。
#
# 【設計方針】
# 「カラムを新しく増やすのは禁忌判定に関わるものだけ」とする。
# 設問は改訂されるため、カラムが増えるほど改訂コストが上がる。
#
# ただし既存カラムへの昇格は落とさない。
# has_implanted_device は contraindication_reasons が参照しており、
# 昇格をやめると「植込み型医療機器あり」の警告が静かに出なくなる。
# under_treatment / taking_medication / pregnancy_weeks / is_breastfeeding も
# 旧実装が設定していたため、同じ理由で維持する。
#
# 一方、コロナワクチン接種回数などの新しい設問はカラムに昇格させず、
# answers から読む参照ヘルパに留める。
#
# 【重要】FLAG_CONTRACT は MedicalQuestionnaireForm の定義と対応している。
# 設問のキー名または選択肢の value を変えると静かに壊れるため、
# test/models/medical_questionnaire_flags_test.rb で契約を検証している。
# テストが落ちたら、テストではなくこちらか設問定義のどちらかを直すこと。
module MedicalQuestionnaireFlags
  extend ActiveSupport::Concern

  # カラムに昇格させるキー => その設問が取りうる value の一覧
  FLAG_CONTRACT = {
    "q2_under_treatment" => %w[no yes],
    "q4_medication"      => %w[no yes],
    "q10_pacemaker"      => %w[no yes],
    "q10_other_device"   => %w[no yes],
    "q13_pregnant"       => %w[no yes unknown],
    "q13_breastfeeding"  => %w[no yes]
  }.freeze

  # 妊娠週数。選択肢が 1〜42 と多いため FLAG_CONTRACT では値まで検証しない。
  WEEKS_KEY = "q13_pregnancy_weeks".freeze

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
  def additional_items? = answer_for("q17_has_additional") == "yes"
  def vaccinated?       = answer_for("q17_vaccinated") == "yes"
  def vaccine_count     = answer_for("q17_vaccine_count").presence
  def covid_infected?   = answer_for("q17_infected") == "yes"
  def covid_infection_count = answer_for("q17_infection_count").presence

  # ── 警告の出し分け ──────────────────────────
  #
  # 2段階に分ける。
  #   contraindicated?     絶対禁忌。「施術できません」（既存・変更しない）
  #   needs_confirmation?  要確認。「確認してください」
  #
  # 植込み型医療機器（ペースメーカー以外）と妊娠「わからない」は、
  # 機器の種類や実際の状況によるためスタッフの確認が要る。
  # 一律に「施術できません」と出すと運用が回らないが、
  # 何も出ないと has_implanted_device を昇格させた意味が無い。
  def needs_confirmation?
    return false if contraindicated?

    confirmation_reasons.any?
  end

  def confirmation_reasons
    reasons = []
    reasons << "植込み型医療機器あり（ペースメーカー以外）" if has_implanted_device?
    reasons << "妊娠の可能性について確認が必要" if pregnancy_unknown?
    reasons
  end

  # ── 昇格 ────────────────────────────────────
  #
  # 既存の before_save コールバックから呼ばれる。
  # コールバックの登録は MedicalQuestionnaire 側に残すこと。
  def promote_flags_from_answers
    # 下書きのうちは常に現行版に追随させる（記入中に設問が改訂された場合、
    # 画面に出ているのは新しい設問のため）。提出済みは当時の版を保持する。
    if form_version.blank? || (respond_to?(:status_draft?) && status_draft?)
      self.form_version = MedicalQuestionnaireForm::VERSION
    end

    self.under_treatment      = answered_yes?("q2_under_treatment")
    self.taking_medication    = answered_yes?("q4_medication")
    self.has_pacemaker        = answered_yes?("q10_pacemaker")
    self.has_implanted_device = answered_yes?("q10_other_device")

    case answer_for("q13_pregnant")
    when "yes"     then assign_pregnancy(pregnant: true,  unknown: false)
    when "unknown" then assign_pregnancy(pregnant: false, unknown: true)
    else                assign_pregnancy(pregnant: false, unknown: false)
    end

    self.is_breastfeeding = answered_yes?("q13_breastfeeding")
  end

  private

  def answered_yes?(key)
    answer_for(key) == "yes"
  end

  # 男性・未回答は「妊娠していない」として扱う。
  # 【13】は female_only のため男性には表示されず、値は常に空になる。
  # 妊娠していないときに週数を残さない（回答を取り消した場合に古い値が残るため）。
  def assign_pregnancy(pregnant:, unknown:)
    self.is_pregnant       = pregnant
    self.pregnancy_unknown = unknown
    self.pregnancy_weeks   = pregnant ? answer_for(WEEKS_KEY).presence&.to_i : nil
  end
end

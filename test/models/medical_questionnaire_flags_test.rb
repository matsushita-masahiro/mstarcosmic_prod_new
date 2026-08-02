# test/models/medical_questionnaire_flags_test.rb
#
# 「設問改訂で禁忌判定が静かに壊れる」のを防ぐためのテスト。
# 設問定義（MedicalQuestionnaireForm）とフラグ昇格（MedicalQuestionnaireFlags）が
# 同じキー・同じ value を見ていることを検証する。
#
# 落ちたときはテストを直さないこと。
# どちらか一方だけが改訂されているという意味なので、両方を揃えて直す。
require "test_helper"

class MedicalQuestionnaireFlagsTest < ActiveSupport::TestCase
  test "昇格対象のキーが設問定義に存在し、選択肢も一致している" do
    MedicalQuestionnaireFlags::FLAG_CONTRACT.each do |key, expected_values|
      question = MedicalQuestionnaireForm.find(key)
      assert question, "設問定義に #{key} がありません"

      actual_values =
        case question[:type]
        when :boolean then MedicalQuestionnaireForm::YES_NO.map { |o| o[:value] }
        else Array(question[:options]).map { |o| o[:value] }
        end

      assert_equal expected_values.sort, actual_values.sort,
                   "#{key} の選択肢が変わっています（禁忌判定の見直しが必要）"
    end
  end

  test "妊娠週数のキーが設問定義に存在する" do
    assert MedicalQuestionnaireForm.find(MedicalQuestionnaireFlags::WEEKS_KEY)
  end

  test "参照キーが設問定義に存在する" do
    MedicalQuestionnaireFlags::REFERENCE_KEYS.each do |key|
      assert MedicalQuestionnaireForm.find(key), "設問定義に #{key} がありません"
    end
  end

  test "フラグ用のカラムが存在する" do
    %w[answers form_version has_pacemaker has_implanted_device
       is_pregnant pregnancy_unknown pregnancy_weeks is_breastfeeding
       under_treatment taking_medication]
      .each { |col| assert_includes MedicalQuestionnaire.column_names, col }
  end

  test "ペースメーカーありでフラグが立つ" do
    q = build_questionnaire("q10_pacemaker" => "yes")
    q.promote_flags_from_answers
    assert q.has_pacemaker
    assert_not q.has_implanted_device
  end

  test "ペースメーカー以外の医療機器でもフラグが立つ" do
    q = build_questionnaire("q10_pacemaker" => "no", "q10_other_device" => "yes")
    q.promote_flags_from_answers
    assert_not q.has_pacemaker
    assert q.has_implanted_device
  end

  test "治療中・服薬中が昇格される" do
    q = build_questionnaire("q2_under_treatment" => "yes", "q4_medication" => "yes")
    q.promote_flags_from_answers
    assert q.under_treatment
    assert q.taking_medication
  end

  test "妊娠中なら週数と授乳状況も昇格される" do
    q = build_questionnaire(
      "q13_pregnant" => "yes",
      "q13_pregnancy_weeks" => "12",
      "q13_breastfeeding" => "yes"
    )
    q.promote_flags_from_answers
    assert q.is_pregnant
    assert_not q.pregnancy_unknown
    assert_equal 12, q.pregnancy_weeks
    assert q.is_breastfeeding
  end

  test "妊娠わからないは pregnancy_unknown になり週数は入らない" do
    q = build_questionnaire("q13_pregnant" => "unknown", "q13_pregnancy_weeks" => "12")
    q.promote_flags_from_answers
    assert_not q.is_pregnant
    assert q.pregnancy_unknown
    assert_nil q.pregnancy_weeks
  end

  test "回答を取り消すとフラグも下がる" do
    q = build_questionnaire(
      "q10_pacemaker" => "yes", "q10_other_device" => "yes",
      "q13_pregnant" => "yes", "q13_pregnancy_weeks" => "20",
      "q2_under_treatment" => "yes", "q4_medication" => "yes"
    )
    q.promote_flags_from_answers

    q.answers = {
      "q10_pacemaker" => "no", "q10_other_device" => "no",
      "q13_pregnant" => "no",
      "q2_under_treatment" => "no", "q4_medication" => "no"
    }
    q.promote_flags_from_answers

    assert_not q.has_pacemaker
    assert_not q.has_implanted_device
    assert_not q.is_pregnant
    assert_not q.pregnancy_unknown
    assert_nil q.pregnancy_weeks
    assert_not q.under_treatment
    assert_not q.taking_medication
  end

  test "未回答でも例外にならない" do
    q = MedicalQuestionnaire.new(answers: nil)
    assert_nothing_raised { q.promote_flags_from_answers }
    assert_not q.has_pacemaker
  end

  test "下書きは現行の form_version に追随する" do
    q = build_questionnaire({})
    q.form_version = "2000-01-01"
    q.promote_flags_from_answers
    assert_equal MedicalQuestionnaireForm::VERSION, q.form_version
  end

  test "植込み型医療機器のみなら要確認になる" do
    q = build_questionnaire("q10_pacemaker" => "no", "q10_other_device" => "yes")
    q.promote_flags_from_answers
    assert_not q.contraindicated?
    assert q.needs_confirmation?
    assert_includes q.confirmation_reasons.join, "植込み型医療機器"
  end

  test "妊娠わからないは要確認になる" do
    q = build_questionnaire("q13_pregnant" => "unknown")
    q.promote_flags_from_answers
    assert_not q.contraindicated?
    assert q.needs_confirmation?
    assert_includes q.confirmation_reasons.join, "妊娠"
  end

  test "絶対禁忌のときは要確認を重ねて出さない" do
    q = build_questionnaire("q10_pacemaker" => "yes", "q10_other_device" => "yes")
    q.promote_flags_from_answers
    assert q.contraindicated?
    assert_not q.needs_confirmation?
  end

  test "該当なしなら要確認も出ない" do
    q = build_questionnaire("q10_pacemaker" => "no", "q13_pregnant" => "no")
    q.promote_flags_from_answers
    assert_not q.contraindicated?
    assert_not q.needs_confirmation?
  end

  private

  def build_questionnaire(answers)
    MedicalQuestionnaire.new(answers: answers, status: :draft)
  end
end

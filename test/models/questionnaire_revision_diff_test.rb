# test/models/questionnaire_revision_diff_test.rb
#
# 訂正版と前版の差分。
#
# ── いちばん大事なところ ────────────────────────
#
# 「施術可否に関わる項目が変わったか」の判定。
# これが警告バナーを出すかどうかを決める。
#
#   変わったのに出ない → 「ペースメーカーあり → なし」が誰にも伝わらない。
#                        訂正機能を作った意味が消える。
#   変わっていないのに出る → 誤字の訂正でも毎回バナーが出る。
#                            常態化して誰も読まなくなり、本番で効かなくなる。
#
# 両方が同時に成立して初めて「禁忌の変化を見ている」と言える。
# 片方だけなら、常に true を返す実装でも常に false を返す実装でも通ってしまう。
#
# ── フラグ一覧をここにも書き写さないこと ──────────────
#
# 判定対象は MedicalQuestionnaireFlags::WARNING_PREDICATES から引く。
# 設問が改訂されて条件が増えたとき、書き写していると増えたぶんが
# 静かに見逃される。下に定数を参照するテストを置いてある。
require "test_helper"

class QuestionnaireRevisionDiffTest < ActiveSupport::TestCase
  setup do
    @patient = User.create!(name: "テスト患者", user_type: "2",
                            email: "diff-#{SecureRandom.hex(6)}@example.com",
                            password: SecureRandom.hex(12))
  end

  test "訂正版でなければ比べる相手がいない" do
    diff = QuestionnaireRevisionDiff.new(create_questionnaire)

    assert_not diff.present?
    assert_not diff.warning_flags_changed?
    assert_empty diff.answer_changes
  end

  # ── 施術可否に関わる項目の変化 ──────────────────

  test "禁忌が あり から なし に変わったら検知する" do
    previous = create_questionnaire(answers: { "q10_pacemaker" => "yes" })
    revision = create_revision(previous, answers: { "q10_pacemaker" => "no" })

    diff = QuestionnaireRevisionDiff.new(revision)

    assert diff.warning_flags_changed?, "禁忌の変化が検知されていません"
    assert_equal [ :has_pacemaker? ], diff.changed_warning_predicates

    change = diff.flag_changes.sole
    assert_equal "ペースメーカー装着", change.label
    assert_equal "あり", change.before
    assert_equal "なし", change.after
  end

  test "禁忌が なし から あり に変わっても検知する" do
    previous = create_questionnaire(answers: { "q10_pacemaker" => "no" })
    revision = create_revision(previous, answers: { "q10_pacemaker" => "yes" })

    assert QuestionnaireRevisionDiff.new(revision).warning_flags_changed?
  end

  # 誤字の訂正でバナーが出ると常態化して誰も読まなくなる。
  test "禁忌に関わらない訂正では検知しない" do
    previous = create_questionnaire(
      answers: { "q10_pacemaker" => "yes", "q7_marital_status" => "single" }
    )
    revision = create_revision(
      previous,
      answers: { "q10_pacemaker" => "yes", "q7_marital_status" => "married" }
    )

    diff = QuestionnaireRevisionDiff.new(revision)

    assert_not diff.warning_flags_changed?,
               "禁忌が変わっていないのにバナーが出ます（常態化して読まれなくなります）"
    assert diff.answer_changes.any?, "回答の差分自体は出ること"
  end

  # 黄色（要確認）のフラグも施術に関わるので対象に含めている。
  # 含めないと「植込み型医療機器あり → なし」が誰にも伝わらない。
  test "要確認のフラグの変化も検知する" do
    previous = create_questionnaire(answers: { "q10_other_device" => "yes" })
    revision = create_revision(previous, answers: { "q10_other_device" => "no" })

    assert QuestionnaireRevisionDiff.new(revision).warning_flags_changed?
  end

  # 対象の一覧を書き写していないことの確認。
  # 定数に条件が増えたら、このテストが自動でその分も要求する。
  test "判定対象は WARNING_PREDICATES と一致する" do
    expected = MedicalQuestionnaireFlags::CONTRAINDICATION_PREDICATES +
               MedicalQuestionnaireFlags::CONFIRMATION_PREDICATES

    assert_equal expected.sort, MedicalQuestionnaireFlags::WARNING_PREDICATES.sort

    MedicalQuestionnaireFlags::WARNING_PREDICATES.each do |predicate|
      assert MedicalQuestionnaire.new.respond_to?(predicate),
             "#{predicate} が MedicalQuestionnaire に無い"
    end
  end

  # ── 回答の差分 ────────────────────────────

  test "旧値から新値へ、設問ラベルと選択肢ラベルで出る" do
    previous = create_questionnaire(answers: { "q10_pacemaker" => "no" })
    revision = create_revision(previous, answers: { "q10_pacemaker" => "yes" })

    change = QuestionnaireRevisionDiff.new(revision).answer_changes.sole

    assert_includes change.label, "【10】", "設問番号が出ていません"
    assert_not_includes change.label, "q10_pacemaker", "キー名が露出しています"
    assert_equal "いいえ", change.before, "生の値が出ています"
    assert_equal "はい", change.after
    assert change.known_question
  end

  test "回答が増えた・消えた場合は未回答と並べて出る" do
    previous = create_questionnaire(answers: {})
    revision = create_revision(previous, answers: { "q7_marital_status" => "married" })

    change = QuestionnaireRevisionDiff.new(revision).answer_changes.sole

    assert_equal QuestionnaireRevisionDiff::BLANK_LABEL, change.before
    assert_equal "既婚", change.after
  end

  test "複数選択の回答は選択肢を並べて出る" do
    previous = create_questionnaire(answers: { "q6_family_history" => [ "糖尿病" ] })
    revision = create_revision(previous,
                               answers: { "q6_family_history" => [ "糖尿病", "高血圧" ] })

    change = QuestionnaireRevisionDiff.new(revision).answer_changes.sole

    assert_equal "糖尿病", change.before
    assert_equal "糖尿病、高血圧", change.after
  end

  test "変わっていない回答は差分に出ない" do
    previous = create_questionnaire(answers: { "q7_marital_status" => "single" })
    revision = create_revision(previous, answers: { "q7_marital_status" => "single" })

    assert_empty QuestionnaireRevisionDiff.new(revision).answer_changes
  end

  # ── 未回答どうしを変更として出さない ──────────────
  #
  # キー無し（nil）・空欄（""）・何も選ばれていない（[]）は、どれも画面では
  # 「（未回答）」と出る。値としては別物なので、畳まないと
  #   機器名: （未回答） → （未回答）
  # という変わっていない行が並ぶ。様式に項目が増えた直後の訂正で出る
  # （前版にはキーごと無く、訂正版は空欄を "" として送るため）。
  #
  # ただし「出さない」だけでは足りない。未回答から回答へ、回答から未回答への
  # 変化は差分の主眼そのものなので、引き続き出ること。

  test "キーが無い前版と空欄の訂正版は変更として出さない" do
    previous = create_questionnaire(answers: {})
    revision = create_revision(previous, answers: { "q10_device_name" => "" })

    assert_empty QuestionnaireRevisionDiff.new(revision).answer_changes
    assert_not QuestionnaireRevisionDiff.new(revision).any_change?
  end

  test "空欄の前版とキーが無い訂正版も変更として出さない" do
    previous = create_questionnaire(answers: { "q10_device_name" => "" })
    revision = create_revision(previous, answers: {})

    assert_empty QuestionnaireRevisionDiff.new(revision).answer_changes
  end

  # 空白だけの文字列も画面には「（未回答）」と出る。
  # 畳まないと結局「（未回答） → （未回答）」の行が残る。
  test "空白だけの回答も未回答として扱う" do
    previous = create_questionnaire(answers: {})
    revision = create_revision(previous, answers: { "q10_device_name" => "  " })

    assert_empty QuestionnaireRevisionDiff.new(revision).answer_changes
  end

  test "複数選択のキー無しと空の選択も変更として出さない" do
    previous = create_questionnaire(answers: {})
    revision = create_revision(previous, answers: { "q6_family_history" => [] })

    assert_empty QuestionnaireRevisionDiff.new(revision).answer_changes
  end

  # ここから「出るべきものは出る」。畳みすぎていないことの確認。
  test "未回答から回答になった変化は出る" do
    previous = create_questionnaire(answers: { "q10_device_name" => "" })
    revision = create_revision(previous, answers: { "q10_device_name" => "人工内耳" })

    change = QuestionnaireRevisionDiff.new(revision).answer_changes.sole

    assert_equal QuestionnaireRevisionDiff::BLANK_LABEL, change.before
    assert_equal "人工内耳", change.after
  end

  test "回答が未回答になった変化は出る" do
    previous = create_questionnaire(answers: { "q10_device_name" => "人工内耳" })
    revision = create_revision(previous, answers: { "q10_device_name" => "" })

    change = QuestionnaireRevisionDiff.new(revision).answer_changes.sole

    assert_equal "人工内耳", change.before
    assert_equal QuestionnaireRevisionDiff::BLANK_LABEL, change.after
  end

  test "複数選択が空から選択ありになった変化は出る" do
    previous = create_questionnaire(answers: { "q6_family_history" => [] })
    revision = create_revision(previous, answers: { "q6_family_history" => [ "糖尿病" ] })

    assert_equal "糖尿病", QuestionnaireRevisionDiff.new(revision).answer_changes.sole.after
  end

  # false を未回答に畳まないこと。
  #
  # 今の様式は「はい / いいえ」を文字列で持つので false は入らないが、
  # blank? / presence で畳むと false も未回答になり、boolean で持つ様式に
  # 変わった瞬間に「いいえ → 未回答」が差分から静かに消える。
  # 見落とすより余分に出るほうが安全なので、値として扱う。
  test "false は未回答に畳まない" do
    previous = create_questionnaire(answers: { "q10_other_device" => false })
    revision = create_revision(previous, answers: {})

    assert_equal [ "q10_other_device" ],
                 QuestionnaireRevisionDiff.new(revision).answer_changes.map(&:key)
  end

  # 様式が違うと片方にしか無い設問がありうる。落ちずにキーで出す。
  test "現在の様式に無い設問はキーのまま出し、その旨が分かる" do
    previous = create_questionnaire(answers: { "q99_removed" => "yes" })
    revision = create_revision(previous, answers: {})

    change = QuestionnaireRevisionDiff.new(revision).answer_changes.sole

    assert_equal "q99_removed", change.label
    assert change.unknown_question?, "現在の様式に無いことが分かりません"
  end

  # 性別は長らく定義の外にあり、訂正すると差分に
  # 「q0_gender（現在の様式にない設問）」と出ていた。
  # 設問番号を持たないので、ラベルは【】なしのまま出る。
  test "性別の変化は設問ラベルと選択肢ラベルで出る" do
    previous = create_questionnaire(answers: { "q0_gender" => "male" })
    revision = create_revision(previous, answers: { "q0_gender" => "female" })

    change = QuestionnaireRevisionDiff.new(revision).answer_changes.sole

    assert_equal "性別", change.label
    assert_not change.unknown_question?, "設問定義から引けていません"
    assert_equal "男性", change.before, "生の値が出ています"
    assert_equal "女性", change.after
  end

  # その他欄（複数選択の自由記入）も設問定義から引けること。
  # collect_all が other を集めていなかったため、
  # 「q6_other（現在の様式にない設問）」と出ていた。
  test "その他欄の変化は項目ラベルで出る" do
    previous = create_questionnaire(answers: { "q6_other" => "膠原病" })
    revision = create_revision(previous, answers: { "q6_other" => "潰瘍性大腸炎" })

    change = QuestionnaireRevisionDiff.new(revision).answer_changes.sole

    assert_equal "その他の難病指定されたもの", change.label
    assert_not change.unknown_question?, "設問定義から引けていません"
    assert_equal "膠原病", change.before
    assert_equal "潰瘍性大腸炎", change.after
  end

  test "様式が違えばそれが分かる" do
    previous = create_questionnaire(form_version: "2026-04-17")
    revision = create_revision(previous, answers: { "q7_marital_status" => "single" })

    assert QuestionnaireRevisionDiff.new(revision).form_version_changed?
  end

  # ── 手書き・人体図 ──────────────────────────

  test "書き直された手書き欄が分かる" do
    previous = create_questionnaire
    previous.handwriting_entries.create!(question_key: "q1_purpose",
                                         input_mode: :keyboard, transcribed_text: "前の内容")
    previous.handwriting_entries.create!(question_key: "q3_history",
                                         input_mode: :keyboard, transcribed_text: "変えない内容")

    revision = create_revision(previous)
    revision.handwriting_entries.create!(question_key: "q1_purpose",
                                         input_mode: :keyboard, transcribed_text: "直した内容")
    revision.handwriting_entries.create!(question_key: "q3_history",
                                         input_mode: :keyboard, transcribed_text: "変えない内容")

    changes = QuestionnaireRevisionDiff.new(revision.reload).handwriting_changes

    assert_equal 1, changes.size, "変わっていない欄まで出ています"
    assert_includes changes.sole.label, "【1】"
  end

  test "人体図の変更が分かる" do
    previous = create_questionnaire
    previous.body_marks.create!(side: :front, x: 0.4, y: 0.3, mark_type: :pain)

    revision = create_revision(previous)
    revision.body_marks.create!(side: :front, x: 0.6, y: 0.3, mark_type: :pain)

    assert QuestionnaireRevisionDiff.new(revision.reload).body_marks_changed?
  end

  test "人体図が同じなら変更なし" do
    previous = create_questionnaire
    previous.body_marks.create!(side: :front, x: 0.4, y: 0.3, mark_type: :pain)

    revision = create_revision(previous)
    revision.body_marks.create!(side: :front, x: 0.4, y: 0.3, mark_type: :pain)

    assert_not QuestionnaireRevisionDiff.new(revision.reload).body_marks_changed?
  end

  private

  def create_questionnaire(**attrs)
    defaults = { status: :submitted, submitted_at: 3.days.ago, answers: {},
                 form_version: MedicalQuestionnaireForm::VERSION }
    @patient.medical_questionnaires.create!(defaults.merge(attrs))
  end

  def create_revision(previous, **attrs)
    create_questionnaire(previous_version: previous, submitted_at: Time.current, **attrs)
  end
end

# test/models/medical_questionnaire_draft_snapshot_test.rb
#
# 記入途中の下書きを、患者端末の localStorage と同じ形で返せることを守る。
#
# 【何を守るか】
# intake のフォームはサーバの下書きを ERB では描かず、この JSON を
# questionnaire_controller.js の復元処理にそのまま渡す。
# 形（キー名・値の型）が端末側とずれると、復元が静かに空振りする。
# saveLocalDraft() の形を変えたら、ここも一緒に変えること。
#
# 【特に大事なところ】
# 空欄を含めないこと。端末側の collectHandwriting() は空欄のキーを落とすため、
# こちらが空欄を含めると verifyRestore() が「戻らなかった欄」と数え、
# restoreVerified が false のまま partial 付きの送信が続く。
# そうなるとサーバは削除を一切しなくなり、患者が消した欄が残り続ける。
#
# PNG（image）を含めないことも守る。restore() は strokes しか見ないので
# 表示には要らず、HTML に base64 を埋めると本文が肥大するだけになる。
require "test_helper"

class MedicalQuestionnaireDraftSnapshotTest < ActiveSupport::TestCase
  # signature_pad の toData() が返す形。端末から届くものと同じ。
  STROKES = [ {
    "penColor" => "#111827", "dotSize" => 0, "minWidth" => 0.6, "maxWidth" => 2.2,
    "velocityFilterWeight" => 0.7, "compositeOperation" => "source-over",
    "points" => [ { "time" => 1_787_230_336_819, "x" => 440, "y" => 79.3, "pressure" => 0.5 } ]
  } ].freeze

  test "answers・手書き・人体図が端末と同じ形で返る" do
    q = create_draft(answers: { "q7_marital_status" => "married" })
    q.handwriting_entries.create!(question_key: "q1_purpose", input_mode: :pen,
                                  strokes: STROKES, canvas_width: 860, canvas_height: 140)
    q.handwriting_entries.create!(question_key: "q3_history", input_mode: :keyboard,
                                  transcribed_text: "五十肩で通院していました")
    q.body_marks.create!(side: :front, x: 0.4, y: 0.3, mark_type: :pain)

    snapshot = q.reload.draft_snapshot

    assert_equal({ "q7_marital_status" => "married" }, snapshot[:answers])

    assert_equal({ mode: "pen", strokes: STROKES, width: 860, height: 140 },
                 snapshot[:handwriting]["q1_purpose"])
    assert_equal({ mode: "keyboard", text: "五十肩で通院していました" },
                 snapshot[:handwriting]["q3_history"])

    assert_equal [ { side: "front", x: 0.4, y: 0.3, mark_type: "pain" } ], snapshot[:bodyMarks]
  end

  # 端末側は x / y を数値で持つ。decimal のまま to_json すると文字列になる。
  test "人体図の座標が数値で返る" do
    q = create_draft
    q.body_marks.create!(side: :back, x: 0.125, y: 0.875, mark_type: :numbness)

    mark = q.reload.draft_snapshot[:bodyMarks].first

    assert_instance_of Float, mark[:x]
    assert_instance_of Float, mark[:y]
    assert_in_delta 0.125, mark[:x], 0.0001
  end

  test "手書きに PNG は含まれない" do
    q = create_draft
    q.handwriting_entries.create!(question_key: "q1_purpose", input_mode: :pen, strokes: STROKES)

    entry = q.reload.draft_snapshot[:handwriting]["q1_purpose"]

    assert_not entry.key?(:image), "サーバの下書きに PNG が含まれています"
    assert_not_includes q.draft_snapshot.to_json, "data:image/png"
  end

  # 空欄を含めると verifyRestore() が「戻らなかった欄」と数えてしまう。
  test "中身が空の欄は含まれない" do
    q = create_draft(answers: { "q7_marital_status" => "single" })
    q.handwriting_entries.create!(question_key: "q1_purpose", input_mode: :pen, strokes: [])
    q.handwriting_entries.create!(question_key: "q3_history", input_mode: :keyboard,
                                  transcribed_text: "")

    assert_empty q.reload.draft_snapshot[:handwriting],
                 "空欄がサーバの下書きに含まれています（partial が付いたままになります）"
  end

  test "savedAt は端末と同じミリ秒で返る" do
    q = create_draft(answers: { "q7_marital_status" => "married" })

    assert_equal (q.updated_at.to_f * 1000).round, q.draft_snapshot[:savedAt]
  end

  # 空を渡すと画面は何も変わらないのに「読み込みました」とだけ出る。
  test "戻せるものが何も無ければ nil" do
    assert_nil create_draft.draft_snapshot
  end

  test "保存されていない下書きは nil" do
    questionnaire = MedicalQuestionnaire.new(user: create_patient,
                                             form_version: MedicalQuestionnaireForm::VERSION)

    assert_nil questionnaire.draft_snapshot
  end

  private

  def create_patient
    User.create!(email: "snapshot-#{SecureRandom.hex(4)}@example.com",
                 name: "患者", password: "password")
  end

  def create_draft(answers: {})
    MedicalQuestionnaire.create!(
      user: create_patient, form_version: MedicalQuestionnaireForm::VERSION,
      status: :draft, answers: answers
    )
  end
end

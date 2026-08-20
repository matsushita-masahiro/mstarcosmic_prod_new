require "test_helper"

# 問診票の確認署名（モデル側）。
#
# ── なぜ署名を入れたか ────────────────────────────
#
# 訂正版は「誰が同意したか」の記録を持たない。
# 「ペースメーカーあり → なし」のような施術可否に直結する変更が、
# 署名なしで最新版になれてしまう。初回・訂正の両方に署名を入れて初めて
# 意味を持つ（訂正だけ守っても、偽造したい人間は初回問診を作り直せばよい）。
#
# ── 検証を無条件にできない理由 ──────────────────────
#
# 署名は「下書きから確定へ移るとき」だけ要る。無条件にすると
#   1. 記入中の autosave（署名前なので当然空）
#   2. 署名の運用開始前に提出された既存レコード（本番11件・staging 12件）
#   3. KarteAttachment.attach! が永続化済みレコードに走らせる record.save
# がすべて落ちる。3 は Consent で一度踏んでいる罠。
# ここではその境界を固定する。
class MedicalQuestionnaireSignatureTest < ActiveSupport::TestCase
  setup do
    @patient = User.create!(email: "sig-model@example.com", name: "患者", password: "password")
  end

  # ── 確定できない条件 ───────────────────────────
  test "署名が無ければ確定できない" do
    questionnaire = draft

    error = assert_raises(ActiveRecord::RecordInvalid) { questionnaire.submit! }

    assert_includes error.record.errors.full_messages, "署名が入力されていません"
    assert questionnaire.reload.status_draft?, "確定していないこと"
  end

  test "署名者名が空なら確定できない" do
    questionnaire = draft

    error = assert_raises(ActiveRecord::RecordInvalid) do
      sign(questionnaire, signer_name: "")
    end

    assert_includes error.record.errors.full_messages, "署名者のお名前が入力されていません"
    assert questionnaire.reload.status_draft?, "確定していないこと"
  end

  # ── 確定できる条件 ────────────────────────────
  test "署名して確定すると submit! を通って submitted になる" do
    questionnaire = draft

    assert sign(questionnaire)

    questionnaire.reload
    assert questionnaire.status_submitted?
    assert_not_nil questionnaire.submitted_at, "submit! を経由していない"
    assert_not_nil questionnaire.signed_at
    assert questionnaire.signed?
  end

  test "署名者名と続柄が保存される" do
    questionnaire = draft

    sign(questionnaire, signer_name: "患者の母", signer_relation: "guardian")

    questionnaire.reload
    assert_equal "患者の母", questionnaire.signer_name
    assert questionnaire.signer_guardian?
  end

  # 座標だけに間引くと筆速・筆順が復元できず、模倣筆跡の検出力が失われる。
  test "署名の各点の time が保存される" do
    questionnaire = draft

    sign(questionnaire)

    points = questionnaire.reload.signature_strokes.first["points"]
    assert points.all? { |p| p["time"].present? },
           "time が落ちている。筆速・筆順が復元できず、模倣の検出力が失われる"
  end

  # ── 二重確定 ─────────────────────────────────
  test "確定済みのものを再度確定できない" do
    questionnaire = draft
    sign(questionnaire, signer_name: "患者")
    first_signed_at = questionnaire.reload.signed_at

    assert_not sign(questionnaire, signer_name: "別人", signer_relation: "guardian"),
               "確定済みなら false を返すこと"

    questionnaire.reload
    assert_equal "患者", questionnaire.signer_name, "署名が上書きされています"
    assert_equal first_signed_at, questionnaire.signed_at
    assert questionnaire.signer_self_signed?
  end

  # ── 既存データ（署名の運用開始前）────────────────────
  test "署名の無い既存レコードでも更新できる" do
    legacy = @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION,
      status: :submitted, submitted_at: 1.year.ago, answers: {}
    )
    assert_not legacy.signed?, "前提: 署名が無いこと"

    legacy.update!(status: :reviewed, reviewed_at: Time.current)

    assert legacy.reload.status_reviewed?,
           "既存の未署名レコードが更新できなくなると、reviewed も画像の添付も落ちる"
  end

  test "記入中の下書きは署名が無くても保存できる" do
    questionnaire = draft

    questionnaire.answers = { "q10_pacemaker" => "no" }

    assert questionnaire.save, "autosave が署名の検証で落ちてはいけない"
  end

  # ── 最新版の判定（submit! を通していることの担保）──────────
  #
  # 確定の経路が submit! を外れると、SQL 側と Ruby 側で最新版が食い違う。
  # test/models/user_test.rb が守っている不変条件を、署名経由の確定でも見る。
  test "署名で確定しても最新版の判定が SQL 側と Ruby 側で一致する" do
    older = draft
    sign(older)
    older.update!(submitted_at: 3.days.ago)

    newer = draft
    sign(newer)
    newer.update!(submitted_at: 1.hour.ago)

    @patient.reload
    assert_equal newer, @patient.latest_questionnaire
    assert_equal newer, @patient.latest_finalized_questionnaire
    assert_equal @patient.latest_questionnaire, @patient.latest_finalized_questionnaire
  end

  private

  def draft
    @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, answers: {}
    )
  end

  def sign(questionnaire, signer_name: "患者", signer_relation: "self_signed")
    questionnaire.sign_and_submit!(
      intake_session: nil, signer_name: signer_name, signer_relation: signer_relation,
      strokes: SIGNATURE_STROKES, ip_address: "203.0.113.7", user_agent: "Test/1.0"
    )
  end
end

require "test_helper"

# 手書き回答を strokes から描き直す。
#
# ── ここで守るもの ─────────────────────────────
#
# 新旧の色分けはカルテだけ。患者の確認画面には出さない。
# 出し分けはフラグではなく、境界インデックスを渡すか渡さないかで決めている。
# 患者側に渡す経路が無ければ、色が出ることもない。
class HandwritingReplayTest < ActionDispatch::IntegrationTest
  BOUNDARY_ATTR = "data-handwriting-replay-boundary-value".freeze

  def group(seed)
    { "penColor" => "#111827", "points" => [
      { "x" => seed.to_f, "y" => seed.to_f,
        "time" => 1_787_230_336_800 + seed, "pressure" => 0.5 }
    ] }
  end

  setup do
    Rails.application.reload_routes_unless_loaded
    @document = ConsentDocument.create!(version: "hw-replay", title: "同意書",
                                        body: "本文", published_at: Time.current)
    @staff = User.create!(email: "hr-staff@example.com", name: "スタッフ",
                          password: "password", user_type: "1")
    @patient = User.create!(email: "hr-pt@example.com", name: "患者", name_kana: "かんじゃ",
                            password: "password", birthday: Date.new(1990, 1, 1),
                            gender: "f", blood_type: "a")
  end

  # ── 1. カルテには境界が渡り、患者側には渡らない ──────────
  test "カルテでは境界インデックスが渡る" do
    v1 = version(strokes: [ group(1), group(2) ])
    v2 = version(previous: v1, strokes: [ group(1), group(2), group(3) ])
    sign_in_staff

    get karte_user_path(@patient, questionnaire_id: v2.id)

    assert_response :success
    assert_select %(div[#{BOUNDARY_ATTR}="2"]), true,
                  "カルテに境界インデックスが渡っていません"
    assert_match(/前回までの記入/, response.body, "凡例が出ていません")
  end

  # この機能でいちばん避けたい失敗。patient 側は同じ partial を描くので、
  # 渡す経路を1つ作るだけで患者の画面に色が出る。
  test "患者の確認画面には境界インデックスが渡らない" do
    # 訂正の実フローで確認画面まで進める。前版があるので、カルテで
    # 同じ問診票を開けば境界が出る状態を作ったうえで患者側を見る。
    previous = version(strokes: [ group(1), group(2) ])
    draft = revise_as_patient(previous, strokes: [ group(1), group(2), group(3) ])

    get intake_questionnaire_confirmation_path

    assert_response :success
    assert_select %(div[data-controller="handwriting-replay"]), true,
                  "前提: 患者側でも canvas で描き直している"
    assert_select %(div[#{BOUNDARY_ATTR}]), false,
                  "患者の確認画面に新旧の境界が渡っています"
    assert_no_match(/前回までの記入/, response.body, "患者の画面に凡例が出ています")

    # 同じ問診票をカルテで開けば境界が出ること。患者側で出ないのが
    # 「そもそも境界が無いから」ではないことを裏から押さえる。
    assert_equal({ "q1_purpose" => 2 }, draft.reload.inherited_stroke_counts)
  end

  # ── 2. 安全弁 ───────────────────────────────
  test "先頭が前版と一致しなければ境界は0で渡る" do
    v1 = version(strokes: [ group(1), group(2) ])
    v2 = version(previous: v1, strokes: [ group(9) ])
    sign_in_staff

    get karte_user_path(@patient, questionnaire_id: v2.id)

    assert_select %(div[#{BOUNDARY_ATTR}="0"]), true,
                  "全消しして書き直した版が「全部が元」として渡っています"
  end

  # ── 3. 前版が無ければ単色 ─────────────────────
  test "初回提出では境界を渡さない" do
    v1 = version(strokes: [ group(1), group(2) ])
    sign_in_staff

    get karte_user_path(@patient, questionnaire_id: v1.id)

    assert_select %(div[data-controller="handwriting-replay"])
    assert_select %(div[#{BOUNDARY_ATTR}]), false, "前版が無いのに境界が渡っています"
    assert_no_match(/前回までの記入/, response.body)
  end

  # ── 4. canvas_width をそのまま渡す ───────────────
  #
  # 端末で変わる値なので、固定値を前提にした実装をしない。
  # 実データでは 334 と 353 の2種類が出ている。
  test "記入時の canvas 寸法がそのまま渡る" do
    narrow = version(strokes: [ group(1) ], canvas_width: 334, canvas_height: 120)
    wide   = version(previous: narrow, strokes: [ group(1) ],
                     canvas_width: 353, canvas_height: 140)
    sign_in_staff

    get karte_user_path(@patient, questionnaire_id: narrow.id)
    assert_select %(div[data-handwriting-replay-width-value="334"])
    assert_select %(div[data-handwriting-replay-height-value="120"])

    get karte_user_path(@patient, questionnaire_id: wide.id)
    assert_select %(div[data-handwriting-replay-width-value="353"])
    assert_select %(div[data-handwriting-replay-height-value="140"])
  end

  # ── 5. PNG が無くても描ける ────────────────────
  #
  # 記入時より canvas が狭いと PNG は保存されない。これまでは
  # 「（手書きあり・画像なし）」としか出せず、患者は自分が書いたものを
  # 確かめないまま署名していた。
  test "PNG が無くても strokes があれば描き直す" do
    v1 = version(strokes: [ group(1), group(2) ])
    sign_in_staff

    get karte_user_path(@patient, questionnaire_id: v1.id)

    assert_select %(div[data-controller="handwriting-replay"])
    assert_no_match(/手書きあり・画像なし/, response.body)
    assert_no_match(/手書きあり・記録なし/, response.body)
  end

  # strokes も PNG も無い欄だけは、復元できないので文言を出す。
  test "strokes も PNG も無ければ記録なしと出す" do
    questionnaire = @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, status: :submitted,
      submitted_at: Time.current, answers: {}
    )
    questionnaire.handwriting_entries.create!(
      question_key: "q1_purpose", input_mode: :pen, strokes: [], canvas_width: 353
    )
    sign_in_staff

    get karte_user_path(@patient, questionnaire_id: questionnaire.id)

    assert_select %(div[data-controller="handwriting-replay"]), false
  end

  private

  def version(strokes:, previous: nil, status: :submitted,
              canvas_width: 353, canvas_height: 140)
    questionnaire = @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, status: status,
      submitted_at: (status == :draft ? nil : Time.current),
      answers: { "q10_pacemaker" => "no" }, previous_version: previous
    )
    questionnaire.handwriting_entries.create!(
      question_key: "q1_purpose", input_mode: :pen, strokes: strokes,
      canvas_width: canvas_width, canvas_height: canvas_height
    )
    questionnaire
  end

  def sign_in_staff
    host! "www.example.com"
    post user_session_path,
         params: { user: { email: @staff.email, password: "password" } }
  end

  # 訂正のセッションで入り、書き足したうえで下書きを作る。
  def revise_as_patient(previous, strokes:)
    Consent.create!(user: @patient, consent_document: @document,
                    agreed_at: Time.current, signer_name: "患者",
                    signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ])
    host! "intake.localhost"
    record = IntakeSession.issue_revision!(patient: @patient, issuer: @staff,
                                           target: previous)
    get intake_entry_path(token: record.raw_token)

    post intake_questionnaires_path, params: {
      answers: { "q10_pacemaker" => "no" }.to_json,
      handwriting: { "q1_purpose" => { "mode" => "pen", "strokes" => strokes,
                                       "width" => 353, "height" => 140 } }.to_json
    }

    @patient.medical_questionnaires.order(:id).last
  end
end

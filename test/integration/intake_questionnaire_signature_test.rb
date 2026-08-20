require "test_helper"

# 記入 → [送信] → 確認画面 → 署名 → 確定。
#
# ── なぜ確認画面を挟むか ──────────────────────────
#
# 訂正版は「誰が同意したか」の記録を持たないまま最新版になれた。
# 「ペースメーカーあり → なし」のような施術可否に直結する変更が
# 署名なしで通るのを止めるのがこの機能。
# 記入の末尾に署名欄を置く形にしないのは、下まで書いた勢いで署名すると
# 「何に署名したのか」が記録として弱いため。
#
# ── ここで守る境界 ───────────────────────────────
#
# [送信] は下書きを保存するだけで、確定させない。
# 確定（submit! / トークンの失効 / 性別の反映）は署名した瞬間にだけ起きる。
# 逆にすると、確認画面から記入画面へ戻れなくなる（トークンが死ぬ）。
class IntakeQuestionnaireSignatureTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes_unless_loaded
    host! "intake.localhost"

    @document = ConsentDocument.create!(
      version: "signature-test", title: "同意書", body: "本文", published_at: Time.current
    )
    @issuer  = User.create!(email: "issuer-sig@example.com", name: "発行者", password: "password")
    @patient = User.create!(email: "patient-sig@example.com", name: "患者 太郎",
                            password: "password", gender: "m")
    Consent.create!(
      user: @patient, consent_document: @document, agreed_at: Time.current,
      signer_name: "患者 太郎", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
    enter
  end

  # ── 1. [送信] では確定しない ─────────────────────
  test "送信しただけでは下書きのままで、確認画面へ送られる" do
    submit(answers: { "q10_pacemaker" => "no" })

    assert_response :created
    assert_equal intake_questionnaire_confirmation_path,
                 JSON.parse(response.body)["redirect_to"]

    questionnaire = @patient.medical_questionnaires.sole
    assert questionnaire.status_draft?, "署名前に確定しています"
    assert_nil questionnaire.submitted_at
  end

  test "送信しただけではトークンが失効しない" do
    submit(answers: {})

    assert @intake_session.reload.active?,
           "ここで失効させると、確認画面から記入画面へ戻れなくなる"
  end

  test "確認画面から記入画面へ戻れて、下書きが残っている" do
    submit(answers: { "q7_marital_status" => "married" })

    get intake_questionnaire_confirmation_path
    assert_response :success

    get intake_questionnaire_path
    assert_response :success

    questionnaire = @patient.medical_questionnaires.sole
    assert questionnaire.status_draft?
    assert_equal "married", questionnaire.answers["q7_marital_status"],
                 "戻ったら書き直しになるのでは、間違いに気づいても直せない"
  end

  # ── 2. 署名で確定する ───────────────────────────
  test "署名して確定すると submitted になり、トークンが失効する" do
    submit(answers: { "q10_pacemaker" => "no" })
    confirm

    assert_response :created
    assert_equal intake_thanks_path, JSON.parse(response.body)["redirect_to"]

    questionnaire = @patient.medical_questionnaires.sole
    assert questionnaire.status_submitted?
    assert_not_nil questionnaire.submitted_at, "submit! を経由していない"
    assert_equal @intake_session, questionnaire.intake_session
    assert_not @intake_session.reload.active?
  end

  test "署名者名・続柄・署名日時が保存される" do
    submit(answers: {})
    confirm(signer_name: "患者 花子", signer_relation: "guardian")

    questionnaire = @patient.medical_questionnaires.sole
    assert_equal "患者 花子", questionnaire.signer_name
    assert questionnaire.signer_guardian?
    assert_not_nil questionnaire.signed_at
  end

  test "署名の座標に time が残っている" do
    submit(answers: {})
    confirm

    points = @patient.medical_questionnaires.sole.signature_strokes.first["points"]
    assert points.all? { |p| p["time"].present? },
           "time を落とすと筆速・筆順が復元できず、模倣の検出力が失われる"
  end

  test "署名画像が添付される" do
    submit(answers: {})
    confirm(image: SIGNATURE_PNG_DATA_URL)

    questionnaire = @patient.medical_questionnaires.sole
    assert questionnaire.signature_image.attached?, "署名画像が添付されていません"
    assert_equal "questionnaire.png", questionnaire.signature_image.filename.to_s
  end

  test "問診票で聞いた性別が確定時に users へ反映される" do
    @patient.update_column(:gender, nil)
    submit(answers: { "q0_gender" => "female" })

    assert_nil @patient.reload.gender, "署名前に反映してはいけない"

    confirm
    assert_equal "f", @patient.reload.gender
  end

  # ── 3. 署名なしでは確定できない ───────────────────
  test "署名が無ければ確定できない" do
    submit(answers: {})
    post intake_questionnaire_confirmation_path,
         params: { signer_name: "患者 太郎", signer_relation: "self_signed" }

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "署名が入力されていません"

    assert @patient.medical_questionnaires.sole.status_draft?
    assert @intake_session.reload.active?, "確定していないのにトークンが失効しています"
  end

  test "署名者名が空なら確定できない" do
    submit(answers: {})
    confirm(signer_name: "  ")

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"], "署名者のお名前が入力されていません"
    assert @patient.medical_questionnaires.sole.status_draft?
  end

  # 二重送信・別タブからの確定。患者にエラーを見せる意味は無い
  # （有効な署名は既にサーバにある）ので、完了画面へ送る。
  test "確定済みのものをもう一度確定しても署名が上書きされない" do
    submit(answers: {})
    confirm(signer_name: "患者 太郎")

    # トークンは失効しているので、確定済みの状態で入り直せる形を作る
    questionnaire = @patient.medical_questionnaires.sole
    enter
    post intake_questionnaire_confirmation_path,
         params: { signer_name: "別人", signer_relation: "guardian",
                   signature_strokes: SIGNATURE_STROKES.to_json }

    assert_response :success
    assert_equal intake_thanks_path, JSON.parse(response.body)["redirect_to"]
    assert_equal "患者 太郎", questionnaire.reload.signer_name
    assert questionnaire.signer_self_signed?
  end

  test "画面に出していない続柄は送られても既定に落ちる" do
    submit(answers: {})
    confirm(signer_relation: "other")

    assert @patient.medical_questionnaires.sole.signer_self_signed?
  end

  # ── 4. 確認画面の中身 ──────────────────────────
  test "確認画面に記入した内容が出る" do
    submit(answers: { "q7_marital_status" => "married" },
           handwriting: { "q1_purpose" => { "mode" => "keyboard", "text" => "肩こりの相談" } })

    get intake_questionnaire_confirmation_path

    assert_response :success
    assert_select "h1", text: /記入内容のご確認/
    assert_match "既婚", response.body
    assert_match "肩こりの相談", response.body
    assert_match "記入内容に相違ないことを確認しました", response.body
  end

  test "下書きが無いのに確認画面を開くと記入画面へ返される" do
    get intake_questionnaire_confirmation_path

    assert_redirected_to intake_questionnaire_path
  end

  # ── 5. 訂正のとき ─────────────────────────────
  test "訂正の確認画面には前版からの変更点が出る" do
    previous = @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, status: :submitted,
      submitted_at: 3.days.ago, answers: { "q7_marital_status" => "single" }
    )
    enter_revision(previous)
    submit(answers: { "q7_marital_status" => "married" })

    get intake_questionnaire_confirmation_path

    assert_response :success
    assert_select "h1", text: /訂正内容のご確認/
    assert_match "前回から変わったところ", response.body
    assert_match "未婚", response.body
    assert_match "既婚", response.body
    assert_match "訂正内容に相違ないことを確認しました", response.body
  end

  test "訂正も署名しなければ確定しない" do
    previous = @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, status: :submitted,
      submitted_at: 3.days.ago, answers: { "q10_pacemaker" => "yes" }
    )
    enter_revision(previous)
    submit(answers: { "q10_pacemaker" => "no" })

    revision = @patient.medical_questionnaires.order(:id).last
    assert revision.status_draft?,
           "施術可否に関わる変更が、署名なしで最新版になってはいけない"
    assert_equal previous, revision.previous_version

    confirm
    assert revision.reload.status_submitted?
    assert_not_nil revision.signed_at
  end

  private

  def enter
    @intake_session = IntakeSession.issue!(patient: @patient, issuer: @issuer)
    get intake_entry_path(token: @intake_session.raw_token)
  end

  def enter_revision(target)
    @intake_session = IntakeSession.issue_revision!(
      patient: @patient, issuer: @issuer, target: target
    )
    get intake_entry_path(token: @intake_session.raw_token)
  end

  def submit(answers: {}, handwriting: nil, body_marks: nil)
    params = { answers: answers.to_json }
    params[:handwriting] = handwriting.to_json unless handwriting.nil?
    params[:body_marks] = body_marks.to_json unless body_marks.nil?
    post intake_questionnaires_path, params: params
  end

  def confirm(signer_name: "患者 太郎", signer_relation: "self_signed", image: nil)
    params = { signer_name: signer_name, signer_relation: signer_relation,
               signature_strokes: SIGNATURE_STROKES.to_json }
    params[:signature_image] = image if image
    post intake_questionnaire_confirmation_path, params: params
  end
end

require "test_helper"

# 血液型（q0_blood_type）の出し分け・訂正での持ち越し・users への反映。
#
# ── この機能の核心 ────────────────────────────────
#
# 血液型は users.blood_type が未設定の患者にだけ聞く（ask_unless）。
# 性別と違って「不明」が正当な答えなので、"unknown" も「訊いた」に数える。
# ここを gender_known? と同じ意味論（認識できる値か）で書くと、
# 答えられない患者に来店のたびに同じ設問を出し続けることになる。
#
# ── 性別と同じ落とし穴を共有している ──────────────────────
#
# 出力しない設問は collectAnswers() が拾えないため、訂正では前版から
# 補わないと回答が静かに消える。判定は
# Intake::QuestionnairesController#skipped_question? の1か所だけが持つ。
class IntakeBloodTypeQuestionTest < ActionDispatch::IntegrationTest
  BLOOD_TYPE_INPUT = %(input[name="answers[q0_blood_type]"]).freeze

  setup do
    Rails.application.reload_routes_unless_loaded
    host! "intake.localhost"

    @document = ConsentDocument.create!(
      version: "blood-type-test", title: "同意書", body: "本文", published_at: Time.current
    )
    @issuer  = User.create!(email: "issuer-blood@example.com", name: "発行者",
                            password: "password")
    # 性別は入れておく。血液型だけを見たいので、性別の設問は出さない。
    @patient = User.create!(email: "patient-blood@example.com", name: "患者 太郎",
                            password: "password", gender: "f", blood_type: nil,
                            birthday: Date.new(1985, 3, 4))
    Consent.create!(
      user: @patient, consent_document: @document, agreed_at: Time.current,
      signer_name: "患者 太郎", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
  end

  # ── 出し分け ───────────────────────────────
  test "血液型が未登録の患者には血液型を聞く" do
    enter
    get intake_questionnaire_path

    assert_response :success
    %w[a b o ab unknown].each do |value|
      assert_select %(#{BLOOD_TYPE_INPUT}[value="#{value}"]), 1,
                    "選択肢 #{value} が出ていません"
    end
  end

  test "血液型が登録済みの患者には聞かない" do
    @patient.update_column(:blood_type, "a")
    enter
    get intake_questionnaire_path

    assert_response :success
    assert_select BLOOD_TYPE_INPUT, false, "分かっている情報を聞き直しています"
  end

  # この機能の核心。ここが壊れると、答えられない患者が来店のたびに
  # 同じことを聞かれる。"unknown" は「訊いたが分からない」で、
  # NULL（まだ訊いていない）とは別物。
  test "不明と答えた患者には次回もう聞かない" do
    @patient.update_column(:blood_type, "unknown")
    enter
    get intake_questionnaire_path

    assert_response :success
    assert_select BLOOD_TYPE_INPUT, false,
                  "「不明」と答えた患者に、来店のたびに同じ設問が出ます"
  end

  # 性別と同じく番号を持たせていない。既存は【1】〜【19】の連番で、
  # 途中に差し込むと以降がすべてずれる。
  test "血液型に設問番号は出ない" do
    enter
    get intake_questionnaire_path

    assert_response :success
    assert_select ".q-label", text: /血液型/
    assert_no_match "【0】", response.body
  end

  # ── ヘッダーとの排他 ────────────────────────────
  #
  # 「設問に出す」と「ヘッダーに出す」は裏返しの関係。片方だけ直すと、
  # 聞いている最中の情報をヘッダーが先に断定する（または登録済みなのに
  # ヘッダーが黙る）状態になる。両方向を対で見る。
  test "未登録なら設問に出てヘッダーには出ない" do
    enter
    get intake_questionnaire_path

    assert_response :success
    assert_select BLOOD_TYPE_INPUT
    assert_select ".intake-meta-sub" do |elements|
      assert_no_match(/型|不明/, elements.first.text,
                      "まだ訊いていない血液型をヘッダーが断定しています")
    end
  end

  test "登録済みなら設問に出ずヘッダーに出る" do
    @patient.update_column(:blood_type, "ab")
    enter
    get intake_questionnaire_path

    assert_response :success
    assert_select BLOOD_TYPE_INPUT, false
    assert_select ".intake-meta-sub", text: /AB型/
  end

  # 「不明」もヘッダーに出す。空欄にするとスタッフからは
  # 「まだ訊いていない」と見分けが付かず、もう一度訊くことになる。
  test "不明もヘッダーに表示する" do
    @patient.update_column(:blood_type, "unknown")
    enter
    get intake_questionnaire_path

    assert_response :success
    assert_select ".intake-meta-sub", text: /不明/
  end

  # ── users への反映 ────────────────────────────
  test "確定すると users.blood_type に入る" do
    enter
    submit(answers: { "q0_blood_type" => "o" })
    confirm

    assert_equal "o", @patient.reload.blood_type,
                 "sync_patient_blood_type! を呼び忘れると、落ちずに値だけ入りません"
  end

  test "不明という回答もそのまま users に入る" do
    enter
    submit(answers: { "q0_blood_type" => "unknown" })
    confirm

    assert_equal "unknown", @patient.reload.blood_type,
                 "未回答扱いにすると、次回また同じ設問が出ます"
  end

  # 回答値をそのまま入れる。変換層を作らない取り決めの確認。
  test "回答値は変換せずそのまま入る" do
    enter
    submit(answers: { "q0_blood_type" => "ab" })
    confirm

    assert_equal "ab", @patient.reload.blood_type
  end

  # 既存値は患者の自己申告より優先する（sync_patient_gender! と同じ取り決め）。
  # 設問が出ないので通常は届かないが、訂正の持ち越しで届きうる。
  test "既に登録済みなら上書きしない" do
    @patient.update_column(:blood_type, "a")
    enter
    submit(answers: { "q0_blood_type" => "b" })
    confirm

    assert_equal "a", @patient.reload.blood_type,
                 "既存の登録が患者の自己申告で上書きされています"
  end

  # 性別の反映を血液型で置き換えてしまっていないこと。
  # どちらも呼び忘れても例外にならず、値が入らないだけで済んでしまう。
  test "性別と血液型が同時に反映される" do
    @patient.update_columns(gender: nil, blood_type: nil)
    enter
    submit(answers: { "q0_gender" => "female", "q0_blood_type" => "b" })
    confirm

    @patient.reload
    assert_equal "f", @patient.gender, "sync_patient_gender! が呼ばれなくなっています"
    assert_equal "b", @patient.blood_type, "sync_patient_blood_type! が呼ばれていません"
  end

  # ── 訂正での持ち越し ────────────────────────────
  #
  # 初回提出で users.blood_type が埋まるので、訂正画面ではもう聞かれない。
  # 出力されない設問は collectAnswers() が拾いようがなく、そのまま保存すると
  # 前版の回答が「未回答」になって消える。性別で踏んだ事故と同じ形。
  test "画面に出さなかった血液型は前版から引き継がれる" do
    @patient.update_column(:blood_type, "o")
    previous = create_previous(answers: { "q0_blood_type" => "o",
                                          "q7_marital_status" => "single" })

    enter_revision(previous)
    submit(answers: { "q7_marital_status" => "married" })

    revision = latest_version
    assert_equal "o", revision.answers["q0_blood_type"],
                 "画面に出ない設問の回答が、訂正のたびに消えます"
    assert_equal "married", revision.answers["q7_marital_status"]
  end

  test "自動保存でも血液型が消えない" do
    @patient.update_column(:blood_type, "unknown")
    previous = create_previous(answers: { "q0_blood_type" => "unknown" })

    enter_revision(previous)
    patch intake_questionnaire_path,
          params: { answers: { "q7_marital_status" => "single" }.to_json }

    assert_response :success
    assert_equal "unknown", latest_version.answers["q0_blood_type"],
                 "30秒ごとの自動保存で消えては、送信まで残りません"
  end

  # ── 確認画面（署名の証跡）────────────────────────
  test "確認画面に血液型が出る" do
    enter
    submit(answers: { "q0_blood_type" => "a" })
    get intake_questionnaire_confirmation_path

    assert_response :success
    assert_match "血液型", response.body
    assert_match "A型", response.body
  end

  test "不明と答えた場合も確認画面に出る" do
    enter
    submit(answers: { "q0_blood_type" => "unknown" })
    get intake_questionnaire_confirmation_path

    assert_response :success
    assert_match "血液型", response.body
    assert_match "不明", response.body
  end

  test "訂正の確認画面にも持ち越した血液型が出る" do
    @patient.update_column(:blood_type, "b")
    previous = create_previous(answers: { "q0_blood_type" => "b" })

    enter_revision(previous)
    submit(answers: { "q7_marital_status" => "married" })
    get intake_questionnaire_confirmation_path

    assert_response :success
    assert_match "B型", response.body
  end

  # ── ひととおりの流れ ────────────────────────────
  #
  # 記入 → 確認 → 署名 → 確定。設問を1つ足したことで途中の
  # どこかが落ちていないことを、通しで確かめる。
  test "記入から確定まで通して動く" do
    enter
    get intake_questionnaire_path
    assert_response :success

    submit(answers: { "q0_blood_type" => "a", "q7_marital_status" => "married" })
    assert_response :created

    get intake_questionnaire_confirmation_path
    assert_response :success

    confirm
    assert_response :created

    questionnaire = latest_version
    assert_predicate questionnaire, :status_submitted?
    assert_equal "a", questionnaire.answers["q0_blood_type"]
    assert_equal "a", @patient.reload.blood_type
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

  def create_previous(answers:)
    @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION,
      status: :submitted, submitted_at: 3.days.ago, answers: answers
    )
  end

  def submit(answers:)
    post intake_questionnaires_path, params: { answers: answers.to_json }
  end

  def confirm
    post intake_questionnaire_confirmation_path,
         params: { signer_name: "患者 太郎", signer_relation: "self_signed",
                   signature_strokes: SIGNATURE_STROKES.to_json }
  end

  def latest_version
    @patient.medical_questionnaires.order(:id).last
  end
end

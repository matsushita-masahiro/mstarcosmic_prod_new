require "test_helper"

# 性別（q0_gender）の出し分けと、訂正での持ち越し。
#
# ── なぜ持ち越しが要るのか ──────────────────────────
#
# 性別は users.gender が未設定の患者にだけ聞く（ask_when_unknown）。
# 初回提出で users.gender が埋まるので、次に開く訂正画面ではもう聞かれない。
# 出力されない設問は collectAnswers() が拾いようがなく、そのまま保存すると
# 前版で答えていた性別が「未回答」になって消える。該当すれば必ず消える。
#
# 実害は限られる（users.gender は残る）が、カルテの差分に
# 「性別 男性 → （未回答）」と出て、スタッフには患者が消したように見える。
#
# ── ここが設計の要 ─────────────────────────────
#
# 補うのは「出力しなかった設問」だけで、「hidden で隠しただけの設問」は補わない。
#   出力しなかった   … 画面に無い＝患者は触れない  → 前版から補う
#   hidden で隠した … 画面にある＝患者が条件を外して消した → 補わない
# 後者まで補うと、患者が「吸わない」に直したのに本数が復活する。
# 条件は Intake::QuestionnairesController#skipped_question? の1か所だけが持ち、
# ビューに渡す @questions もそこから作る。
class IntakeGenderQuestionTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes_unless_loaded
    host! "intake.localhost"

    @document = ConsentDocument.create!(
      version: "gender-test", title: "同意書", body: "本文", published_at: Time.current
    )
    @issuer  = User.create!(email: "issuer-gender@example.com", name: "発行者",
                            password: "password")
    @patient = User.create!(email: "patient-gender@example.com", name: "患者 太郎",
                            password: "password", gender: nil)
    Consent.create!(
      user: @patient, consent_document: @document, agreed_at: Time.current,
      signer_name: "患者 太郎", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
  end

  # ── 出し分け ───────────────────────────────
  test "性別が未設定の患者には性別を聞く" do
    enter
    get intake_questionnaire_path

    assert_response :success
    assert_select %(input[name="answers[q0_gender]"][value="female"])
    assert_select %(input[name="answers[q0_gender]"][value="male"])
  end

  test "性別が分かっている患者には聞かない" do
    @patient.update_column(:gender, "f")
    enter
    get intake_questionnaire_path

    assert_response :success
    assert_select %(input[name="answers[q0_gender]"]), false,
                  "分かっている情報を聞き直しています"
  end

  # 出力しないだけで、設問そのものは定義にある。
  # 番号を持たせていないので「【0】」は出ない。
  test "性別に設問番号は出ない" do
    enter
    get intake_questionnaire_path

    assert_no_match "【0】", response.body
  end

  # ── 訂正での持ち越し ────────────────────────────
  test "画面に出さなかった性別は前版から引き継がれる" do
    @patient.update_column(:gender, "m")
    previous = create_previous(answers: { "q0_gender" => "male",
                                          "q7_marital_status" => "single" })

    enter_revision(previous)
    submit(answers: { "q7_marital_status" => "married" })

    revision = latest_version
    assert_equal "male", revision.answers["q0_gender"],
                 "画面に出ない設問の回答が、訂正のたびに消えます"
    assert_equal "married", revision.answers["q7_marital_status"]
  end

  test "自動保存でも性別が消えない" do
    @patient.update_column(:gender, "f")
    previous = create_previous(answers: { "q0_gender" => "female" })

    enter_revision(previous)
    patch intake_questionnaire_path, params: { answers: { "q7_marital_status" => "single" }.to_json }

    assert_response :success
    assert_equal "female", latest_version.answers["q0_gender"],
                 "30秒ごとの自動保存で消えては、送信まで残りません"
  end

  # 画面に出している設問は、届いた内容がそのまま正。
  # 患者が選び直して「未回答」にしたものを前版で埋め戻さない。
  test "画面に出した設問は前版で埋め戻さない" do
    previous = create_previous(answers: { "q0_gender" => "male" })

    enter_revision(previous)
    submit(answers: { "q0_gender" => "female" })

    assert_equal "female", latest_version.answers["q0_gender"],
                 "訂正した内容が前版で上書きされています"
  end

  # ここが「出力しなかった」と「hidden で隠した」の区別。
  # 【8】喫煙を「吸う」→「吸わない」に直すと、本数は画面上で消える
  # （conditional-field が値をクリアする）。前版から復活してはいけない。
  test "条件付き表示で隠れただけの設問は持ち越さない" do
    @patient.update_column(:gender, "m")
    previous = create_previous(answers: { "q0_gender" => "male",
                                          "q8_smoking" => "yes", "q8_per_day" => "6-10" })

    enter_revision(previous)
    submit(answers: { "q8_smoking" => "no", "q8_per_day" => "" })

    revision = latest_version
    assert_equal "male", revision.answers["q0_gender"], "前提: 出力しない設問は補うこと"
    assert_predicate revision.answers["q8_per_day"], :blank?,
                     "患者が消した回答が前版から復活しています"
  end

  test "初回記入では前版が無いので何も補わない" do
    @patient.update_column(:gender, "f")
    enter
    submit(answers: { "q7_marital_status" => "single" })

    assert_equal({ "q7_marital_status" => "single" }, latest_version.answers)
  end

  # ── 確認画面（署名の証跡）────────────────────────
  #
  # 回答一覧は QUESTIONS を走査している。定義に無かった頃は、性別を答えた
  # 患者が「性別だけ確認できないまま署名する」ことになっていた。
  test "確認画面に性別が出る" do
    enter
    submit(answers: { "q0_gender" => "female" })

    get intake_questionnaire_confirmation_path

    assert_response :success
    assert_match "性別", response.body
    assert_match "女性", response.body
  end

  test "訂正の確認画面にも持ち越した性別が出る" do
    @patient.update_column(:gender, "f")
    previous = create_previous(answers: { "q0_gender" => "female" })

    enter_revision(previous)
    submit(answers: { "q7_marital_status" => "married" })
    get intake_questionnaire_confirmation_path

    assert_response :success
    assert_match "女性", response.body
  end

  # 持ち越した値でも users.gender への反映は従来どおり動くこと。
  # （既に値がある患者では上書きしない、が反映処理そのものの取り決め）
  test "性別を聞いた初回は確定時に users へ反映される" do
    enter
    submit(answers: { "q0_gender" => "female" })
    confirm

    assert_equal "f", @patient.reload.gender
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

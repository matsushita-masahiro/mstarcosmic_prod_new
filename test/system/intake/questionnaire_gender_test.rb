require "application_system_test_case"

# 性別（q0_gender）を設問定義に取り込んだことを、実ブラウザで通す。
#
# ── なぜ実ブラウザで見るのか ────────────────────────
#
# 訂正で性別が消えていたのは「サーバが保存に失敗していた」からではなく、
# 設問が DOM に出力されず collectAnswers() が拾えなかったから。
# 何が画面に出て、何が送られるのかはブラウザでしか確かめられない。
#
# ── ここで見分けたい2つ ─────────────────────────
#
#   出力しない（性別）        画面に無い → 患者は触れない → 前版から補う
#   hidden で隠す（【8】本数）画面にある → 患者が消した   → 補わない
#
# サーバ側のテスト（test/integration/intake_gender_question_test.rb）は
# 「届いた回答をどう保存するか」までしか見られない。
# 「そもそも何が届くのか」がここで決まる。
class Intake::QuestionnaireGenderTest < ApplicationSystemTestCase
  setup do
    @original_app_host = Capybara.app_host
    @original_include_port = Capybara.always_include_port
    Capybara.always_include_port = true
    Capybara.app_host = "http://intake.localhost"

    document = ConsentDocument.create!(
      version: "gender-system-test", title: "同意書", body: "本文",
      published_at: Time.current
    )
    @issuer = User.create!(email: "issuer-gender-sys@example.com", name: "発行者",
                           password: "password")
    @patient = User.create!(email: "patient-gender-sys@example.com", name: "患者 太郎",
                            password: "password", gender: "f")
    Consent.create!(
      user: @patient, consent_document: document, agreed_at: Time.current,
      signer_name: "患者 太郎", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
  end

  teardown do
    Capybara.app_host = @original_app_host
    Capybara.always_include_port = @original_include_port
  end

  # 本丸。訂正で性別が消えず、隠れただけの設問は消えること。
  test "訂正で性別が消えず、隠れただけの設問は復活しない" do
    previous = create_previous_version
    open_revision(previous)

    # users.gender が埋まっているので、性別は出力そのものがされない
    # （出力されていれば hidden でも当たる visible: :all で見る）。
    assert_no_selector %(input[name="answers[q0_gender]"]), visible: :all

    # 【8】喫煙を「吸う」→「吸わない」。本数は画面上で消える。
    choose_radio("q8_smoking", "no")

    click_on "記入内容を送信する"
    assert_current_path intake_questionnaire_confirmation_path, wait: 10

    # 患者が署名する画面に性別が出ていること。
    # 出ていなければ「確認していない項目に署名した」ことになる。
    assert_text "性別"
    assert_text "女性"

    sign_and_confirm
    assert_current_path intake_thanks_path, wait: 10

    revision = @patient.medical_questionnaires.order(:id).last
    assert_equal "female", revision.answers["q0_gender"],
                 "画面に出さなかった設問の回答が、訂正で消えています"
    assert_predicate revision.answers["q8_per_day"], :blank?,
                     "患者が消した回答が前版から復活しています"
  end

  # 必須の判定を設問定義（required）から導けていること。
  # 以前は validateRequired() に性別のキーとラベルを直書きしていた。
  test "性別が未設定なら聞かれ、答えないと送信できない" do
    @patient.update_column(:gender, nil)
    open_initial

    assert_selector %(input[name="answers[q0_gender]"][value="male"])
    choose_radio("q10_pacemaker", "no")

    click_on "記入内容を送信する"
    assert_selector '[data-questionnaire-target="status"]',
                    text: "未回答の項目があります: 性別"

    choose_radio("q0_gender", "male")
    click_on "記入内容を送信する"
    assert_current_path intake_questionnaire_confirmation_path, wait: 10
  end

  private

  # 前版。性別は答えてあり、users.gender も埋まっている状態
  # （初回提出の sync_patient_gender! が埋めるので、訂正では必ずこうなる）。
  def create_previous_version
    @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION,
      status: :submitted, submitted_at: 3.days.ago,
      answers: {
        "q0_gender" => "female",
        "q8_smoking" => "yes", "q8_per_day" => "6-10",
        "q10_pacemaker" => "no", "q13_pregnant" => "no"
      }
    )
  end

  def open_revision(previous)
    record = IntakeSession.issue_revision!(patient: @patient, issuer: @issuer, target: previous)
    visit "/s/#{record.raw_token}"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'
    # 前版の復元が終わるまで待つ（復元前に触ると上書きされる）
    assert_selector %(input[name="answers[q8_smoking]"][value="yes"]:checked), visible: :all
  end

  def open_initial
    record = IntakeSession.issue!(patient: @patient, issuer: @issuer)
    visit "/s/#{record.raw_token}"
    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'
  end

  def choose_radio(key, value)
    find(%(input[name="answers[#{key}]"][value="#{value}"])).click
  end

  def sign_and_confirm
    canvas = find('[data-signature-pad-target="canvas"]')
    page.driver.browser.action
        .move_to(canvas.native, 10, 10)
        .click_and_hold.move_by(40, 20).move_by(40, -10).release.perform
    click_on "上記の内容で確定する"
  end
end

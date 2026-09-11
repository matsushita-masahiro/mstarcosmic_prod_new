require "test_helper"

# スタッフ追記が患者の画面に出ないこと。
#
# この機能でいちばん避けたい失敗。追記はスタッフ同士の申し送りで、
# 患者に読ませる前提で書かれていない。
#
# ── なぜ3画面すべてを見るのか ──────────────────────
#
# 患者向けの確認画面は karte/users/_answer を直接描いている
# （intake/questionnaire_confirmations/show.html.erb）。カルテと患者で
# 同じ partial を共有しているため、「カルテの表示部品を足す」だけで
# 患者の画面に出る経路がある。
#
# 記入画面と同意書は別の組み立てだが、ヘッダー（intake/_patient_header）を
# 共有している。追記をヘッダー側や shared/ に置くと、そちらから漏れる。
# 経路が違うので、1画面通っても他が通るとは限らない。
class IntakeAnnotationNotLeakedTest < ActionDispatch::IntegrationTest
  # 追記に使う文字列。画面に出ていたら必ず引っかかるよう、
  # 他のどこにも出ない語にしておく。
  SECRET = "スタッフ限定メモ_ZZ9".freeze

  setup do
    Rails.application.reload_routes_unless_loaded
    host! "intake.localhost"

    @document = ConsentDocument.create!(
      version: "annotation-leak-test", title: "同意書", body: "本文",
      published_at: Time.current
    )
    @staff = User.create!(email: "leak-staff@example.com", name: "山田スタッフ",
                          password: "password", user_type: "1")
    @patient = User.create!(email: "leak-patient@example.com", name: "患者",
                            name_kana: "かんじゃ", password: "password",
                            birthday: Date.new(1990, 1, 1), gender: "f",
                            blood_type: "a")
    Consent.create!(user: @patient, consent_document: @document,
                    agreed_at: Time.current, signer_name: "患者",
                    signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ])
  end

  test "記入画面に追記が出ない" do
    questionnaire = enter_and_start_draft
    annotate!(questionnaire)

    get intake_questionnaire_path

    assert_response :success
    assert_no_leak
  end

  # いちばん危ない画面。karte/users/_answer をそのまま描いている。
  test "確認画面に追記が出ない" do
    questionnaire = enter_and_submit_draft
    annotate!(questionnaire)

    get intake_questionnaire_confirmation_path

    assert_response :success
    assert_match(/ペースメーカー/, response.body,
                 "前提: 追記を付けた設問そのものは確認画面に出ている")
    assert_no_leak
  end

  test "同意書の画面に追記が出ない" do
    questionnaire = enter_and_submit_draft
    annotate!(questionnaire)
    Consent.delete_all

    enter
    get new_intake_consent_path

    assert_response :success
    assert_no_leak
  end

  # 上の3件が「そもそも追記が作られていない」で通っていないことを押さえる。
  # 患者側に出ないことだけを見ると、作成が壊れていても全部通ってしまう。
  test "前提として、同じ追記がカルテには出ている" do
    questionnaire = enter_and_submit_draft
    annotate!(questionnaire)

    host! "www.example.com"
    post user_session_path, params: { user: { email: @staff.email, password: "password" } }
    get karte_user_path(@patient, questionnaire_id: questionnaire.id)

    assert_response :success
    assert_match(/#{SECRET}/, response.body,
                 "カルテにも出ていません。患者側の判定が空振りしています")
  end

  private

  def assert_no_leak
    assert_no_match(/#{SECRET}/, response.body, "患者の画面にスタッフ追記が出ています")
    assert_no_match(/スタッフ追記/, response.body, "患者の画面に追記の見出しが出ています")
    assert_no_match(/山田スタッフ/, response.body, "患者の画面にスタッフ名が出ています")
  end

  # 追記は q10_pacemaker に付ける。確認画面に実際に描かれている設問でないと、
  # 「設問ごと出ていないから漏れなかった」だけになり、判定が空振りする。
  # q1_purpose は手書き設問で、handwriting_entries が無いと描かれない。
  def annotate!(questionnaire)
    QuestionnaireAnnotation.create!(
      medical_questionnaire: questionnaire, question_key: "q10_pacemaker",
      body: SECRET, staff: @staff
    )
  end

  def enter
    record = IntakeSession.issue!(patient: @patient, issuer: @staff)
    get intake_entry_path(token: record.raw_token)
  end

  # 記入画面まで進み、下書きを1件作る。
  def enter_and_start_draft
    enter
    get intake_questionnaire_path
    @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, status: :draft,
      answers: { "q1_purpose" => "肩こりの相談" }
    )
  end

  # 確認画面が見られる状態まで進める。
  def enter_and_submit_draft
    enter
    post intake_questionnaires_path,
         params: { answers: { "q1_purpose" => "肩こりの相談",
                              "q10_pacemaker" => "no" }.to_json }
    @patient.medical_questionnaires.order(:id).last
  end
end

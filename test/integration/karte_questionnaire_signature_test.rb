require "test_helper"

# カルテ側での確認署名の表示。
#
# ── なぜ既存レコードの回帰まで見るのか ──────────────────
#
# 署名の運用を始める前に提出された問診票が本番に11件・staging に12件ある。
# 遡って署名させることはできないので、これらは signed_at が nil のまま残る。
# 表示側が「署名は必ずある」前提で書かれていると、その11件のカルテだけが
# 開けなくなる。患者の記録が読めなくなるのは、署名機能そのものより重い障害。
#
# ── 未署名を警告にしない判断 ─────────────────────────
#
# 既存11件がすべて警告になると常態化して誰も読まなくなり、
# 本当に見てほしい禁忌の警告まで一緒に流される。
# 未署名は患者の状態ではなく記録の性質なので、事実だけを控えめに出す。
# この判断が変わるなら、下の「警告バナーにしない」テストも一緒に直すこと。
class KarteQuestionnaireSignatureTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    Rails.application.reload_routes_unless_loaded
    Warden.test_mode!

    @staff = User.create!(email: "staff-sig@example.com", name: "スタッフ",
                          password: "password", user_type: "1")
    @patient = User.create!(email: "patient-karte-sig@example.com", name: "患者",
                            password: "password")
    login_as @staff, scope: :user
  end

  teardown { Warden.test_reset! }

  test "署名者名・続柄・署名日時が出る" do
    questionnaire = signed_questionnaire(signer_name: "患者 花子", signer_relation: "guardian")

    get karte_user_path(@patient, questionnaire_id: questionnaire.id)

    assert_response :success
    assert_match "患者 花子", response.body
    assert_match "代理人", response.body
    assert_match "内容を確認して署名", response.body
  end

  test "本人の署名は本人と表示される" do
    questionnaire = signed_questionnaire(signer_relation: "self_signed")

    get karte_user_path(@patient, questionnaire_id: questionnaire.id)

    assert_match "（本人）", response.body
  end

  test "署名画像が表示される" do
    questionnaire = signed_questionnaire
    KarteAttachment.attach!(record: questionnaire, name: :signature_image,
                            data_url: SIGNATURE_PNG_DATA_URL,
                            user_id: @patient.id, label: "questionnaire")
    assert questionnaire.reload.signature_image.attached?, "前提: 添付されていること"

    get karte_user_path(@patient, questionnaire_id: questionnaire.id)

    assert_response :success
    assert_select "img[src*='questionnaire.png']", 1,
                  "署名画像が表示されていません"
  end

  # ── 既存データ（署名の運用開始前）────────────────────
  test "署名の無い問診票でもカルテが開ける" do
    legacy = unsigned_questionnaire

    get karte_user_path(@patient, questionnaire_id: legacy.id)

    assert_response :success
    assert_match "確認署名なし", response.body
  end

  test "署名の無い問診票は履歴でも見分けられる" do
    unsigned_questionnaire

    get karte_user_path(@patient)

    assert_response :success
    assert_match "署名なし", response.body
  end

  test "署名済みの問診票には履歴に署名なしと出ない" do
    signed_questionnaire

    get karte_user_path(@patient)

    assert_response :success
    assert_no_match(/署名なし/, response.body)
  end

  # 下書きはまだ署名する段階に来ていないので、履歴にもパネルにも印を付けない。
  # 「署名なし」は状態の説明になっておらず、記入中に見ると壊れて見える。
  test "下書きには署名なしと出ない" do
    @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, answers: {}
    )

    get karte_user_path(@patient)

    assert_response :success
    assert_no_match(/署名なし/, response.body)
  end

  # 未署名を赤・黄のバナーにすると、既存11件で常態化して
  # 禁忌の警告まで一緒に読み飛ばされる。
  test "未署名は警告バナーにはしない" do
    unsigned_questionnaire

    get karte_user_path(@patient)

    assert_no_match(/施術できません/, response.body)
    assert_no_match(/確認してください/, response.body)
  end

  private

  def unsigned_questionnaire
    @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION,
      status: :submitted, submitted_at: 1.year.ago, answers: { "q10_pacemaker" => "no" }
    )
  end

  def signed_questionnaire(signer_name: "患者", signer_relation: "self_signed")
    questionnaire = @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, answers: { "q10_pacemaker" => "no" }
    )
    questionnaire.sign_and_submit!(
      intake_session: nil, signer_name: signer_name, signer_relation: signer_relation,
      strokes: SIGNATURE_STROKES
    )
    questionnaire.reload
  end
end

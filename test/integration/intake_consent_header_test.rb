require "test_helper"

# 同意書画面のヘッダーが、patient_profile の有無で壊れないこと。
#
# ── 直した事故 ────────────────────────────────
#
# ヘッダーは `current_patient.patient_profile&.name_kana` を見ていた。
# ところが name_kana は 20260802052015_cleanup_patient_profiles で
# patient_profiles から削除されている（氏名・カナ・電話・生年月日・性別は
# users 側が正、という取り決め）。
#
# `&.` は「レシーバが nil なら nil」であって「メソッドが無ければ nil」ではない。
# patient_profile が無い患者では nil.presence で偶然フォールバックして動くが、
# レコードがある患者では NoMethodError で 500 になる。
# 住所などを登録した患者だけが同意書を開けない、という壊れ方をする。
#
# そのため「レコードあり」を必ず含める。無い側だけを見ていると、
# 同じ間違いを入れ直しても素通りする。
class IntakeConsentHeaderTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes_unless_loaded
    host! "intake.localhost"

    @document = ConsentDocument.create!(
      version: "consent-header-test", title: "同意書", body: "本文",
      published_at: Time.current
    )
    @issuer  = User.create!(email: "issuer-consent-header@example.com",
                            name: "発行者", password: "password")
    @patient = User.create!(email: "patient-consent-header@example.com",
                            name: "患者 太郎", name_kana: "かんじゃ たろう",
                            password: "password")
  end

  test "patient_profile が無い患者でも同意書が開ける" do
    assert_nil @patient.patient_profile, "前提: プロフィール未登録の患者"

    enter
    get new_intake_consent_path

    assert_response :success
    assert_match "かんじゃ たろう", response.body
  end

  # 本丸。以前はここで NoMethodError になっていた。
  test "patient_profile がある患者でも同意書が開ける" do
    PatientProfile.create!(user: @patient, postal_code: "1000001",
                           prefecture: "東京都", city: "千代田区")

    enter
    get new_intake_consent_path

    assert_response :success
    assert_match "かんじゃ たろう", response.body
  end

  # カナが無い患者は氏名に落ちる。プロフィールの有無に関係なく同じ。
  test "カナが無い患者は氏名で表示される" do
    @patient.update_columns(name_kana: nil)
    PatientProfile.create!(user: @patient, postal_code: "1000001")

    enter
    get new_intake_consent_path

    assert_response :success
    assert_match "患者 太郎", response.body
  end

  private

  def enter
    session_record = IntakeSession.issue!(patient: @patient, issuer: @issuer)
    get intake_entry_path(token: session_record.raw_token)
  end
end

require "test_helper"

# 修正用QRの発行と、入口の振り分け。
#
# ── 何を守るか ────────────────────────────────
#
# 1. 発行したトークンに purpose と対象の版が正しく入ること
#    入っていないと、入口が訂正だと気づけず通常の記入画面へ送る。
#    患者は前版の内容が無い空のフォームに書き直すことになる。
#
# 2. 対象が「その系列の末端」になること
#    v2 を2回続けて修正するとき、2回目も v2 を対象にすると v2 に訂正版が
#    2つ並列にぶら下がり、どちらが有効か決まらなくなる。
#
# 3. 他人の問診票を対象にできないこと
#    その患者の記録に別人の版がぶら下がる。
#
# 4. 下書きを対象にできないこと
#    提出していない版に訂正版を作っても、何を直したのか記録にならない。
#
# ── 第1段階の範囲 ──────────────────────────────
#
# 訂正画面はまだ無い。入口は暫定で問診票へ送る（前版は復元されない）。
# 訂正用のQRを本番のスタッフに案内するのは第2段階が入ってから。
class KarteRevisionTokenTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Rails.application.reload_routes_unless_loaded

    @staff = User.create!(email: "staff-revision@example.com", name: "スタッフ",
                          password: "password", user_type: "1")
    @patient = User.create!(email: "patient-revision@example.com", name: "患者",
                            password: "password", user_type: "2")
    sign_in @staff
  end

  test "修正用のトークンに purpose と対象の版が入る" do
    target = create_questionnaire

    post karte_user_intake_sessions_path(@patient), params: { questionnaire_id: target.id }

    issued = IntakeSession.order(:id).last
    assert issued.purpose_revision?, "purpose が revision になっていません"
    assert_equal target, issued.target_questionnaire
  end

  test "questionnaire_id を渡さなければ従来どおり新規記入のトークンになる" do
    post karte_user_intake_sessions_path(@patient)

    issued = IntakeSession.order(:id).last
    assert issued.purpose_initial?
    assert_nil issued.target_questionnaire
  end

  # 鎖になることの保証。並列にぶら下がらせない。
  test "訂正済みの版を修正すると、対象は系列の末端になる" do
    v1 = create_questionnaire
    v1b = create_questionnaire(previous_version: v1)

    post karte_user_intake_sessions_path(@patient), params: { questionnaire_id: v1.id }

    assert_equal v1b, IntakeSession.order(:id).last.target_questionnaire,
                 "指定された版をそのまま対象にしています（訂正版が並列になります）"
  end

  # 記入途中の訂正版があるときは、その手前を対象にして続きから書かせる。
  test "訂正版が下書きなら、対象はその前の確定版のまま" do
    v1 = create_questionnaire
    create_questionnaire(previous_version: v1, status: :draft, submitted_at: nil)

    post karte_user_intake_sessions_path(@patient), params: { questionnaire_id: v1.id }

    assert_equal v1, IntakeSession.order(:id).last.target_questionnaire
  end

  test "他人の問診票は対象にできない" do
    other = User.create!(email: "other-revision@example.com", name: "別の患者",
                         password: "password", user_type: "2")
    foreign = other.medical_questionnaires.create!(
      status: :submitted, submitted_at: Time.current, answers: {}
    )

    assert_no_difference "IntakeSession.count" do
      post karte_user_intake_sessions_path(@patient), params: { questionnaire_id: foreign.id }
    end
    assert_response :not_found
  end

  test "下書きは対象にできない" do
    draft = create_questionnaire(status: :draft, submitted_at: nil)

    assert_no_difference "IntakeSession.count" do
      post karte_user_intake_sessions_path(@patient), params: { questionnaire_id: draft.id }
    end
    assert_response :not_found
  end

  # ── 入口の振り分け ──────────────────────────────

  test "修正用のトークンで入ると同意書を経由しない" do
    sign_consent!
    target = create_questionnaire
    record = IntakeSession.issue_revision!(patient: @patient, issuer: @staff, target: target)

    host! "intake.localhost"
    get "/s/#{record.raw_token}"

    # TODO(第2段階): 訂正画面ができたらそちらへ変わる
    assert_redirected_to intake_questionnaire_path
  end

  # 訂正は署名済みの患者にしか発行しないが、未署名でも同意書へ戻さない。
  # 前版があるということは、その時点で署名は済んでいる。
  test "修正用のトークンは未署名でも同意書へ戻らない" do
    target = create_questionnaire
    record = IntakeSession.issue_revision!(patient: @patient, issuer: @staff, target: target)

    host! "intake.localhost"
    get "/s/#{record.raw_token}"

    assert_redirected_to intake_questionnaire_path
  end

  test "新規記入のトークンは従来どおり署名の有無で分かれる" do
    record = IntakeSession.issue!(patient: @patient, issuer: @staff)

    host! "intake.localhost"
    get "/s/#{record.raw_token}"
    assert_redirected_to new_intake_consent_path

    sign_consent!
    signed = IntakeSession.issue!(patient: @patient, issuer: @staff)
    get "/s/#{signed.raw_token}"
    assert_redirected_to intake_questionnaire_path
  end

  private

  def create_questionnaire(**attrs)
    defaults = { status: :submitted, submitted_at: Time.current, answers: {} }
    @patient.medical_questionnaires.create!(defaults.merge(attrs))
  end

  def sign_consent!
    document = ConsentDocument.current || ConsentDocument.create!(
      version: "revision-token-test", title: "同意書", body: "本文", published_at: Time.current
    )
    Consent.create!(user: @patient, consent_document: document, agreed_at: Time.current,
                    signer_name: "患者", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ])
  end
end

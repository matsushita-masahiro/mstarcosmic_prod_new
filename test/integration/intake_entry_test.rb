require "test_helper"

# QR の入口（GET /s/:token）が、署名済みの患者を同意書へ送り返さないことを守る。
#
# ── 直した事故 ────────────────────────────────
#
# 入口はトークンを受け取ったあと、署名の有無を見ずに同意書画面へ飛ばしていた。
# そのため同じQRを2回目に開くと、署名済みでも同意書が出る。
# 患者がそこで署名すると、同意書レコードが増える。
#
# 本番で実際に起きていた（2名・4件）。同一来店・同一署名者で
# 30秒差と7分差の重複が残っている。再来店ではない。
#
# session[:intake_token] は Cookie セッションなので端末ごとに別物で、
# 「もう署名した」を Cookie で判定することはできない。別端末で開けば
# 必ず未署名に見える。判定はサーバ側の事実（Consent）で行う。
#
# 問診票側（questionnaires#show）にも同じガードがあったが、入口が
# 問診票を経由しないため働く機会が無かった。ガードは経路上にないと効かない。
#
# ── 既存の重複データについて ──────────────────────
#
# 本番の4件は消していない。どれも有効な署名で、残っていて害は無い。
# 消すかどうかは原因を止めてから別途判断する。
# そのため consents に DB の unique 制約は入れていない
# （既存の重複があるとマイグレーションが通らない）。
class IntakeEntryTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.reload_routes_unless_loaded

    @document = ConsentDocument.create!(
      version: "entry-test", title: "同意書", body: "本文", published_at: Time.current
    )
    @issuer  = User.create!(email: "issuer-entry@example.com", name: "発行者", password: "password")
    @patient = User.create!(email: "patient-entry@example.com", name: "患者", password: "password")
    host! "intake.localhost"
  end

  # 本丸。本番で起きていた事故をここで固定する。
  test "署名済みの患者が同じQRを開くと同意書を経由せず問診票へ行く" do
    sign_consent!

    get "/s/#{issue_session.raw_token}"

    assert_redirected_to intake_questionnaire_path
    follow_redirect!
    assert_response :success
  end

  test "未署名の患者が開くと同意書へ行く" do
    get "/s/#{issue_session.raw_token}"

    assert_redirected_to new_intake_consent_path
    follow_redirect!
    assert_response :success
  end

  test "期限切れのトークンは従来どおり expired へ行く" do
    record = issue_session
    record.update!(expires_at: 1.minute.ago)

    get "/s/#{record.raw_token}"

    assert_redirected_to intake_expired_path
  end

  test "使えないトークンは expired へ行く" do
    get "/s/#{SecureRandom.urlsafe_base64(32)}"

    assert_redirected_to intake_expired_path
  end

  # 入口を直しても、戻るボタンや URL 直打ちでここへ来られる。
  test "署名済みの患者が同意書画面を開こうとしても問診票へ戻される" do
    sign_consent!
    enter_intake

    get new_intake_consent_path

    assert_redirected_to intake_questionnaire_path
  end

  # 開いたまま放置された同意書画面から送信される経路が残る。
  test "署名済みの患者が署名を送っても2件目は作られない" do
    sign_consent!
    enter_intake

    assert_no_difference "Consent.count" do
      post intake_consent_path, params: {
        signer_name: "患者", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ].to_json
      }
    end

    assert_response :success
    assert_equal intake_questionnaire_path, response.parsed_body["redirect_to"],
                 "エラーを見せず問診票へ送ること（署名は既にサーバにある）"
  end

  test "未署名なら従来どおり署名できる" do
    enter_intake

    assert_difference "Consent.count", 1 do
      post intake_consent_path, params: {
        signer_name: "患者", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ].to_json
      }
    end

    assert_response :created
  end

  # 版が変われば再署名が要る。制約が広すぎないことの確認。
  test "同意書が改訂されれば署名済みの患者でも同意書へ行く" do
    sign_consent!
    @document.update!(archived_at: Time.current)
    ConsentDocument.create!(
      version: "entry-test-v2", title: "同意書", body: "改訂した本文", published_at: Time.current
    )

    get "/s/#{issue_session.raw_token}"

    assert_redirected_to new_intake_consent_path
  end

  private

  def issue_session
    IntakeSession.issue!(patient: @patient, issuer: @issuer)
  end

  # 入口を通ってセッションを作る（以降の患者側リクエストで使う）。
  def enter_intake
    get "/s/#{issue_session.raw_token}"
  end

  def sign_consent!
    Consent.create!(
      user: @patient, consent_document: @document, agreed_at: Time.current,
      signer_name: "患者", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
  end
end

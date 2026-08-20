# test/models/consent_test.rb
#
# 同じ患者が同じ版に2件署名することを、モデル層でも止める。
#
# 入口（sessions#show）とコントローラ（consents#new / #create）で弾いているが、
# どちらも「見てから作る」ので、同時に2回送信されると素通りする。
# 実害は同意書レコードが増えることで、患者にもスタッフにも見えない。
#
# 【DB の unique 制約は入れていない】
# 本番に既に重複が残っている（2名・4件）ため、マイグレーションが通らない。
# 重複を消してから改めて検討すること。それまではここが最後の砦になる。
#
# 【on: :create に限っている理由】
# 既存の重複を更新できなくしないため。署名画像は保存後に attach するので、
# そこで走る save がこの検証で落ちると、画像だけ付かない事故になる。
require "test_helper"

class ConsentTest < ActiveSupport::TestCase
  setup do
    @document = ConsentDocument.create!(
      version: "consent-model-test", title: "同意書", body: "本文", published_at: Time.current
    )
    @patient = User.create!(email: "patient-consent-model@example.com", name: "患者",
                            password: "password")
  end

  test "同じ患者が同じ版に2件目を作れない" do
    create_consent!

    duplicate = build_consent

    assert_not duplicate.valid?, "同じ版への2件目が保存できてしまいます"
    assert_includes duplicate.errors.full_messages, "この同意書には既に署名済みです"
  end

  test "版が違えば署名できる" do
    create_consent!
    revised = ConsentDocument.create!(
      version: "consent-model-test-v2", title: "同意書", body: "改訂した本文",
      published_at: Time.current
    )

    assert build_consent(document: revised).valid?,
           "改訂版に署名できません（制約が広すぎます）"
  end

  test "患者が違えば同じ版に署名できる" do
    create_consent!
    other = User.create!(email: "other-consent-model@example.com", name: "別の患者",
                         password: "password")

    assert build_consent(patient: other).valid?
  end

  # 本番に残っている重複を更新できなくしないこと。
  # ここが :create 限定でないと、署名画像の attach（保存後に走る save）が
  # 落ちて画像だけ付かない。
  test "既にある重複レコードは更新できる" do
    first = create_consent!
    second = build_consent
    second.save!(validate: false)   # 本番に残っている状態を作る

    assert second.update(signer_name: "あとから直した名前"),
           "既存の重複が更新できません（署名画像の添付が落ちます）"
    assert first.update(signer_name: "こちらも直せること")
  end

  private

  def build_consent(patient: @patient, document: @document)
    Consent.new(
      user: patient, consent_document: document, agreed_at: Time.current,
      signer_name: "患者", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
  end

  def create_consent!(**args) = build_consent(**args).tap(&:save!)
end

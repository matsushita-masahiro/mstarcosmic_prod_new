# test/models/consent_document_editing_test.rb
#
# 同意書の編集可否と公開の扱いを守るテスト。
#
# 【なぜ必要か】
# Consent は consent_document を参照しているだけで、署名時の本文を持たない。
# 本文を書き換えると、過去の署名が「いま表示されている文言に同意した」ことに
# なってしまい、同意書として成立しなくなる。
# 「署名済みは編集させない」はこの案件で最も壊してはいけない不変条件。
#
# 【このテストの限界】
# ここで守るのはモデル層とコントローラの分岐であって、
# DB を直接更新された場合は防げない（intact? がその検知用）。
require "test_helper"

class ConsentDocumentEditingTest < ActiveSupport::TestCase
  test "署名済みの同意書は destroy できない" do
    doc = published_document
    sign(doc)

    assert_not doc.destroy
    assert doc.errors.any?
    assert ConsentDocument.exists?(doc.id)
  end

  test "署名が無ければ destroy できる" do
    doc = published_document
    assert doc.destroy
  end

  test "current は published のうち published_at が最新の1件" do
    old = create_document(version: "t-old", published_at: 2.days.ago)
    recent = create_document(version: "t-new", published_at: 1.hour.ago)
    create_document(version: "t-draft", published_at: nil)

    assert_equal recent, ConsentDocument.current
    assert_not_equal old, ConsentDocument.current
  end

  test "アーカイブしたものは current に選ばれない" do
    doc = create_document(version: "t-archived", published_at: 1.hour.ago)
    assert_equal doc, ConsentDocument.current

    doc.update!(archived_at: Time.current)
    assert_nil ConsentDocument.current
  end

  test "新しいバージョンを公開すると旧版の署名者は未署名扱いになる" do
    old = create_document(version: "t-v1", published_at: 2.days.ago)
    user = signing_user
    sign(old, user: user)
    assert Consent.current_for?(user)

    create_document(version: "t-v2", published_at: Time.current)
    assert_not Consent.current_for?(user),
               "新バージョン公開後も署名済み扱いになっています"
  end

  test "本文を変えるとダイジェストが再計算され intact? を保つ" do
    doc = published_document
    doc.update!(body: "変更後の本文")
    assert doc.intact?
  end

  test "DB を直接書き換えると intact? が false になる" do
    doc = published_document
    doc.update_column(:body, "改ざんされた本文")

    assert_not doc.reload.intact?,
               "ダイジェストによる改ざん検知が効いていません"
  end

  test "バージョンは重複できない" do
    create_document(version: "t-dup", published_at: Time.current)
    duplicate = ConsentDocument.new(version: "t-dup", title: "別", body: "別")

    assert_not duplicate.valid?
    assert duplicate.errors[:version].any?
  end

  private

  def create_document(version:, published_at:)
    ConsentDocument.create!(
      version: version, title: "テスト同意書", body: "本文",
      published_at: published_at
    )
  end

  def published_document
    create_document(version: "t-#{SecureRandom.hex(4)}", published_at: Time.current)
  end

  def signing_user
    User.create!(name: "テスト患者", user_type: "2",
                 email: "consent-test-#{SecureRandom.hex(6)}@example.com",
                 password: SecureRandom.hex(12))
  end

  def sign(document, user: signing_user)
    Consent.create!(
      user: user, consent_document: document,
      agreed_at: Time.current, signer_name: "テスト",
      signature_strokes: [{ "x" => 1 }]
    )
  end
end

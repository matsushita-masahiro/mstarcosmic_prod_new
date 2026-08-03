require "test_helper"

# 同意書管理画面（Karte::ConsentDocumentsController）。
#
# ── このファイルが守っているもの ──────────────────────
#
# 1.【最重要】署名済みの同意書を変更させないこと（edit / update / destroy の3経路）
#
#    Consent は consent_document を参照しているだけで署名時の本文を持たない。
#    本文を書き換えると、過去の署名が「いま表示されている文言に同意した」ことに
#    なってしまい、同意書として成立しなくなる。
#
#    3経路で守りの厚さが違うので、それぞれ独立したテストにしてある。
#      destroy … has_many :consents, dependent: :restrict_with_error があり
#                モデル層でも止まる（consent_document_editing_test.rb が担当）
#      edit / update … before_action :ensure_editable だけが防いでいる。
#                ここが唯一の防波堤なので、消しても気づけるようにする。
#
# 2. 公開の流れ（新規作成 → 下書き → 公開）と、公開が患者側に反映されること
#
# 3. 公開中が無くなったときに気づけること
#    一覧の警告と、患者側が expired(410) になること。
#    公開中ゼロは「患者が同意書を書けない」状態なので、静かに壊れると気づけない。
#
# 4. 版番号の重複回避と、既存版からの本文引き継ぎ
#
# ── 注意 ────────────────────────────────────────
# スタッフと患者は実際には別クライアント（PC と iPad）。
# intake は入口で reset_session するため、1つのテスト内で同居させると
# スタッフのログインが消える。患者側を見るテストではログインを使わない。
#
# モデル層の不変条件は test/models/consent_document_editing_test.rb が担当。
class ConsentAdminTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    # routes は遅延ロードのため、先に読ませないと Devise.mappings が空で sign_in が落ちる
    Rails.application.reload_routes_unless_loaded

    @staff = User.create!(email: "staff-consent-admin@example.com", name: "スタッフ",
                          password: "password", user_type: "1")
    sign_in @staff
  end

  # ── 1. 署名済みは変更させない ──────────────────────

  test "署名済みの同意書は編集画面に入れない" do
    document = signed_document

    get edit_karte_consent_document_path(document)

    assert_redirected_to karte_consent_document_path(document)
    assert_match(/署名済みの同意書は変更できません/, flash[:alert])
  end

  # ensure_editable が唯一の防波堤。ここが外れると過去の署名の意味が変わる。
  test "署名済みの同意書は更新できない" do
    document = signed_document

    patch karte_consent_document_path(document),
          params: { consent_document: { body: "書き換えた本文", title: "書き換えたタイトル" } }

    assert_redirected_to karte_consent_document_path(document)
    document.reload
    assert_equal "元の本文", document.body, "署名済みの本文が書き換えられています"
    assert_equal "同意書", document.title, "署名済みのタイトルが書き換えられています"
  end

  test "署名済みの同意書は削除できない" do
    document = signed_document

    assert_no_difference "ConsentDocument.count" do
      delete karte_consent_document_path(document)
    end
    assert ConsentDocument.exists?(document.id)
  end

  test "署名済みの同意書は編集・削除ボタンを出さない" do
    document = signed_document

    get karte_consent_document_path(document)

    assert_response :success
    assert_no_match(/#{Regexp.escape(edit_karte_consent_document_path(document))}/,
                    response.body, "編集リンクが出ています")
    assert_match "1 名が署名済みのため", response.body
  end

  test "署名が無ければ編集・更新・削除できる" do
    document = ConsentDocument.create!(version: "v-draft", title: "下書き", body: "本文")

    get edit_karte_consent_document_path(document)
    assert_response :success

    patch karte_consent_document_path(document),
          params: { consent_document: { body: "直した本文" } }
    assert_equal "直した本文", document.reload.body

    assert_difference "ConsentDocument.count", -1 do
      delete karte_consent_document_path(document)
    end
  end

  # ── 2. 公開の流れ ────────────────────────────────

  test "新規作成から下書き保存・内容確認・公開まで通る" do
    get new_karte_consent_document_path
    assert_response :success
    assert_match(/value="#{Date.current.strftime('%Y-%m-%d')}"/, response.body,
                 "版番号の初期値が入ること")

    assert_difference "ConsentDocument.count", 1 do
      post karte_consent_documents_path, params: {
        consent_document: { version: "v-flow", title: "同意書", body: "第1条\n本文です。" }
      }
    end
    document = ConsentDocument.find_by(version: "v-flow")
    assert_redirected_to karte_consent_document_path(document)
    follow_redirect!

    # 保存しただけでは公開されない
    assert_nil document.published_at
    assert_match "下書き", response.body
    assert_match "本文です。", response.body, "公開前に内容を確認できること"
    assert_nil ConsentDocument.current, "下書きは current にならない"

    post publish_karte_consent_document_path(document)
    assert_redirected_to karte_consent_document_path(document)
    follow_redirect!
    assert_match "公開中", response.body
    assert_equal document, ConsentDocument.current
  end

  test "公開中のバージョンが切り替わると患者側の文言も切り替わる" do
    ConsentDocument.create!(version: "v-old", title: "旧同意書",
                            body: "古い文言です", published_at: 2.days.ago)
    patient = create_patient("a")

    visit_intake_consent(patient)
    assert_response :success
    assert_match "古い文言です", response.body

    # publish アクション自体は「新規作成から…公開まで通る」で検証済み
    ConsentDocument.create!(version: "v-new", title: "新同意書",
                            body: "新しい文言です", published_at: Time.current)

    visit_intake_consent(patient)
    assert_response :success
    assert_match "新しい文言です", response.body
    assert_no_match(/古い文言です/, response.body)
  end

  # ── 3. 公開中が無くなったとき ───────────────────────

  test "アーカイブで公開中が無くなると一覧に警告が出る" do
    document = ConsentDocument.create!(version: "v-arch", title: "同意書",
                                       body: "本文", published_at: Time.current)

    post archive_karte_consent_document_path(document)

    assert_redirected_to karte_consent_documents_path
    assert_match(/公開中の同意書が無くなりました/, flash[:notice])
    assert_nil ConsentDocument.current

    follow_redirect!
    assert_match "公開中の同意書がありません", response.body
    assert_match "患者側の同意書ページが開けない状態です", response.body
  end

  test "公開中が無いとき患者側は expired へ飛ぶ" do
    document = ConsentDocument.create!(version: "v-arch2", title: "同意書",
                                       body: "本文", published_at: Time.current)
    patient = create_patient("b")

    visit_intake_consent(patient)
    assert_response :success

    document.update!(archived_at: Time.current)
    assert_nil ConsentDocument.current

    visit_intake_consent(patient)   # /s/:token → consent#new
    assert_redirected_to intake_expired_path
    follow_redirect!
    assert_response :gone
  end

  # ── 4. 一覧・新規作成の補助 ────────────────────────

  test "管理者メニューから一覧に入れる" do
    get karte_users_path
    assert_response :success
    assert_match karte_consent_documents_path, response.body, "メニューにリンクが出ること"

    get karte_consent_documents_path
    assert_response :success
    assert_match "同意書の管理", response.body
    assert_match "公開中の同意書がありません", response.body, "1件も無ければ警告が出ること"
  end

  test "版番号の初期値は既存と重複しない" do
    base = Date.current.strftime("%Y-%m-%d")
    ConsentDocument.create!(version: base, title: "t", body: "b")

    get new_karte_consent_document_path

    assert_response :success
    assert_match(/value="#{base}-2"/, response.body)
  end

  test "既存の版から本文を引き継いで新バージョンを作れる" do
    source = ConsentDocument.create!(version: "v-src", title: "元タイトル",
                                     body: "引き継ぐ本文", published_at: Time.current)

    get new_karte_consent_document_path(from: source.id)

    assert_response :success
    assert_match "引き継ぐ本文", response.body
    assert_match "元タイトル", response.body
  end

  private

  # 署名が1件ある公開中のバージョン
  def signed_document
    document = ConsentDocument.create!(version: "v-signed", title: "同意書",
                                       body: "元の本文", published_at: Time.current)
    Consent.create!(user: create_patient(SecureRandom.hex(3)), consent_document: document,
                    agreed_at: Time.current, signer_name: "本人",
                    signature_strokes: [ { "x" => 1 } ])
    document
  end

  def create_patient(suffix)
    User.create!(email: "patient-consent-#{suffix}@example.com", name: "患者#{suffix}",
                 password: "password")
  end

  # 患者側の同意書ページを開く。
  # intake は入口で reset_session するため、これを呼ぶとスタッフはログアウトする。
  # 患者側を見るテストではスタッフの操作を行わないこと。
  def visit_intake_consent(patient)
    record = IntakeSession.issue!(patient: patient, issuer: @staff)
    host! "intake.localhost"
    get "/s/#{record.raw_token}"
    follow_redirect!
  end
end

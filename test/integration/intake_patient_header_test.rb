require "test_helper"

# 患者向けヘッダーの2行目（生年月日・年齢・性別）。
#
# 出る側と出ない側を対で見る。項目ごと消す仕様なので、判定を間違えて
# 常に消しても「出ない」テストだけなら全部通ってしまう。
#
# 性別についてはもう1つ守るものがある。ヘッダーに性別が出るのは
# users.gender が分かっている患者だけで、その患者には問診票が
# q0_gender を聞かない（ask_unless）。逆に聞いている患者には
# ヘッダーに出さない。この排他が崩れると、同じ画面で性別を2回見せるか、
# 答えている最中の項目を先に断定して見せることになる。
class IntakePatientHeaderTest < ActionDispatch::IntegrationTest
  # 年齢は「今日」で変わる。同意書の有効性もセッションの期限も現在時刻を見るので、
  # 一部の request だけ時刻を動かすと前提の方が崩れる。テスト全体を固定する。
  TODAY = Time.zone.local(2026, 8, 30, 10, 0, 0)

  setup do
    Rails.application.reload_routes_unless_loaded
    host! "intake.localhost"
    travel_to TODAY

    @document = ConsentDocument.create!(
      version: "patient-header-test", title: "同意書", body: "本文",
      published_at: Time.current
    )
    @issuer  = User.create!(email: "issuer-header@example.com", name: "発行者",
                            password: "password")
    @patient = User.create!(email: "patient-header@example.com", name: "橋場 みれい",
                            name_kana: "はしばみれい", password: "password",
                            birthday: Date.new(1985, 3, 4), gender: "f")
    sign_consent!
  end

  # ── 出る側 ──────────────────────────────
  test "生年月日と性別のある患者は2行目が出る" do
    enter
    get intake_questionnaire_path

    assert_response :success
    assert_select "p.intake-meta", /はしばみれい 様/
    assert_select "p.intake-meta", /会員No\. #{@patient.karte_member_no}/
    assert_select "p.intake-meta-sub", "生年月日：1985年3月4日（41歳） ／ 性別：女性"
  end

  # ラベルは3項目すべてに付く。血液型のラベルは特に省けない。
  # 生年月日と性別は値だけで何の項目か分かるが、「不明」は単独では読めない。
  test "血液型まで揃った患者は3項目ともラベル付きで出る" do
    @patient.update_column(:blood_type, "a")
    enter
    get intake_questionnaire_path

    assert_response :success
    assert_select "p.intake-meta-sub",
                  "生年月日：1985年3月4日（41歳） ／ 性別：女性 ／ 血液型：A型"
  end

  # ラベルは値と同じ要素に入れる。外側（ビューや書式文字列）に置くと、
  # 値が落ちた項目でラベルと区切り記号だけが残る。それを見張る。
  #
  # 判定は必ず p.intake-meta-sub の中だけを見ること。この患者は性別も
  # 血液型も未設定なので、問診票の設問側には「性別」「血液型」の文字が
  # 出ている（ask_unless で聞かれる）。ページ全体を見ると、2行目から
  # ラベルが消えていなくても設問の文字で判定が濁る。
  test "欠けた項目のラベルは2行目から区切り記号ごと消える" do
    @patient.update_columns(gender: nil, blood_type: nil)
    enter
    get intake_questionnaire_path

    assert_select "p.intake-meta-sub", "生年月日：1985年3月4日（41歳）"
    assert_select "p.intake-meta-sub", { text: /性別/, count: 0 },
                  "値の無い性別のラベルが2行目に残っています"
    assert_select "p.intake-meta-sub", { text: /血液型/, count: 0 },
                  "値の無い血液型のラベルが2行目に残っています"
    assert_select "p.intake-meta-sub", { text: /／/, count: 0 },
                  "区切り記号だけが2行目に残っています"

    # 設問側には出ていること。上の count: 0 が「ページに無いから通った」
    # のではなく「2行目に無いから通った」ことを、ここで裏から押さえる。
    assert_select %(input[name="answers[q0_gender]"])
    assert_select %(input[name="answers[q0_blood_type]"])
  end

  # 生値が患者の目に触れないこと。ここが漏れると "f" と書かれた画面を
  # 患者が見ることになる。
  test "性別の生値は画面に出ない" do
    enter
    get intake_questionnaire_path

    assert_select "p.intake-meta-sub", /女性/
    assert_no_match(/／\s*f\b/, response.body)
  end

  test "確認画面にも2行目が出る" do
    enter
    post intake_questionnaires_path, params: { answers: { "q10_pacemaker" => "no" }.to_json }
    get intake_questionnaire_confirmation_path

    assert_response :success
    assert_select "p.intake-meta-sub", "生年月日：1985年3月4日（41歳） ／ 性別：女性"
  end

  test "同意書にも2行目が出る" do
    Consent.delete_all
    enter
    get new_intake_consent_path

    assert_response :success
    assert_select "p.intake-meta-sub", "生年月日：1985年3月4日（41歳） ／ 性別：女性"
  end

  # ── 出ない側 ─────────────────────────────
  test "生年月日が無ければ年齢ごと出さず、性別だけ残る" do
    @patient.update_column(:birthday, nil)
    enter
    get intake_questionnaire_path

    assert_response :success
    assert_select "p.intake-meta-sub", "性別：女性"
    assert_no_match "歳", css_select("p.intake-meta-sub").first.text
  end

  test "生年月日も性別も無ければ2行目そのものを出さない" do
    @patient.update_columns(birthday: nil, gender: nil)
    enter
    get intake_questionnaire_path

    assert_response :success
    assert_select "p.intake-meta", /はしばみれい 様/, "1行目は従来どおり出ること"
    assert_select "p.intake-meta-sub", false,
                  "区切り記号だけの空行が残っています"
  end

  test "判別できない性別は出さず、未登録の文言も出さない" do
    @patient.update_column(:gender, "unknown")
    enter
    get intake_questionnaire_path

    assert_response :success
    assert_select "p.intake-meta-sub", "生年月日：1985年3月4日（41歳）"
    assert_no_match "未登録", response.body
  end

  # ── ヘッダーと q0_gender の排他 ─────────────────────
  test "性別が分かる患者はヘッダーに出て設問は聞かれない" do
    enter
    get intake_questionnaire_path

    assert_select "p.intake-meta-sub", /女性/
    assert_select %(input[name="answers[q0_gender]"]), false,
                  "ヘッダーに出したうえで設問でも聞いています"
  end

  test "性別が分からない患者はヘッダーに出ず設問で聞かれる" do
    @patient.update_column(:gender, nil)
    enter
    get intake_questionnaire_path

    assert_select "p.intake-meta-sub", { text: /女性|男性/, count: 0 },
                  "答えている最中の項目を先に断定して見せています"
    assert_select %(input[name="answers[q0_gender]"][value="female"])
    assert_select %(input[name="answers[q0_gender]"][value="male"])
  end

  # 2行目が続くときだけ1行目の間隔を詰める。詰めるかどうかは
  # 2行目の有無と必ず一致していること。
  test "2行目の有無と1行目の詰めクラスが一致する" do
    enter
    get intake_questionnaire_path
    assert_select "p.intake-meta.has-sub"

    @patient.update_columns(birthday: nil, gender: nil)
    get intake_questionnaire_path
    assert_select "p.intake-meta.has-sub", false
  end

  private

  def enter
    record = IntakeSession.issue!(patient: @patient, issuer: @issuer)
    get intake_entry_path(token: record.raw_token)
  end

  def sign_consent!
    Consent.create!(
      user: @patient, consent_document: @document, agreed_at: Time.current,
      signer_name: "橋場 みれい", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
  end
end

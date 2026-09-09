require "application_system_test_case"

# ヘッダーに生年月日・年齢・性別を足したあとも、患者が最後まで進めること。
#
# ── なぜ実ブラウザで見るのか ────────────────────────
#
# ヘッダーは記入・確認・同意書の3画面で共有している。表示だけの変更に見えるが、
# 壊すとしたら「画面は出るが送信まで辿り着けない」形になる。サーバ側の
# 表示テスト（test/integration/intake_patient_header_test.rb）は各画面が
# 200 を返すところまでしか見られないので、記入から確定までを一度通しておく。
#
# ── ここで見たい排他 ───────────────────────────
#
# 性別が分かる患者 → ヘッダーに出る／設問 q0_gender は出ない
# 分からない患者   → ヘッダーに出ない／設問で聞かれる
# どちらかだけを見ると、両方に出す（2回聞く）か両方に出さない
# （どこにも性別が無い）状態を見逃す。
class Intake::PatientHeaderTest < ApplicationSystemTestCase
  # 年齢は「今日」で変わるので固定する。同意書の有効性とセッションの期限も
  # 現在時刻を見るため、レコードを作る前から止めておく。
  TODAY = Time.zone.local(2026, 8, 30, 10, 0, 0)

  setup do
    @original_app_host = Capybara.app_host
    @original_include_port = Capybara.always_include_port
    Capybara.always_include_port = true
    Capybara.app_host = "http://intake.localhost"
    travel_to TODAY

    @document = ConsentDocument.create!(
      version: "patient-header-system-test", title: "同意書", body: "本文",
      published_at: Time.current
    )
    @issuer = User.create!(email: "issuer-header-sys@example.com", name: "発行者",
                           password: "password")
    @patient = User.create!(email: "patient-header-sys@example.com", name: "橋場 みれい",
                            name_kana: "はしばみれい", password: "password",
                            birthday: Date.new(1985, 3, 4), gender: "f")
    Consent.create!(
      user: @patient, consent_document: @document, agreed_at: Time.current,
      signer_name: "橋場 みれい", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
    @intake_session = IntakeSession.issue!(patient: @patient, issuer: @issuer)
  end

  teardown do
    Capybara.app_host = @original_app_host
    Capybara.always_include_port = @original_include_port
  end

  # 本丸。ヘッダーを2行にしても記入〜確認〜署名〜確定が通ること。
  # ブロックされる側だけでなく、正常系が最後まで終わることを見る。
  test "2行のヘッダーが出た状態で記入から確定まで通る" do
    open_questionnaire

    assert_selector "p.intake-meta", text: "はしばみれい 様"
    assert_selector "p.intake-meta", text: "会員No. #{@patient.karte_member_no}"
    assert_selector "p.intake-meta-sub", text: "生年月日：1985年3月4日（41歳） ／ 性別：女性"

    # 分かっている情報は聞かない。ヘッダーと設問の二重取りにしない。
    assert_no_selector %(input[name="answers[q0_gender]"]), visible: :all

    fill_and_send

    # 確認画面にも同じヘッダーが出ること。署名する画面なので、
    # 誰として署名しているかが見えている必要がある。
    assert_selector "p.intake-meta-sub", text: "生年月日：1985年3月4日（41歳） ／ 性別：女性"

    sign_and_confirm
    assert_current_path intake_thanks_path, wait: 10
    assert_text "ありがとうございました"

    questionnaire = @patient.medical_questionnaires.sole
    assert questionnaire.status_submitted?, "ヘッダー変更で送信が止まっています"
    assert_not_nil questionnaire.signed_at
  end

  test "生年月日が無い患者では2行目が出ないまま記入から確定まで通る" do
    @patient.update_columns(birthday: nil, gender: nil)
    open_questionnaire

    assert_selector "p.intake-meta", text: "はしばみれい 様"
    assert_no_selector "p.intake-meta-sub"

    # 性別が分からないので、こちらは設問で聞かれる。
    assert_selector %(input[name="answers[q0_gender]"][value="female"])

    choose_radio("q0_gender", "female")
    fill_and_send
    sign_and_confirm
    assert_current_path intake_thanks_path, wait: 10

    assert @patient.medical_questionnaires.sole.status_submitted?
    assert_equal "f", @patient.reload.gender, "答えた性別が users に反映されていません"
  end

  # 生年月日だけ分かっている患者。片方欠けても区切り記号が残らないこと。
  test "性別だけ分からない患者は生年月日のみを出して設問で聞く" do
    @patient.update_columns(gender: nil)
    open_questionnaire

    assert_selector "p.intake-meta-sub", text: "生年月日：1985年3月4日（41歳）"
    assert_no_selector "p.intake-meta-sub", text: "／"
    assert_selector %(input[name="answers[q0_gender]"][value="female"])
  end

  # 同意書は問診票より前に出る画面。ここでもヘッダーは同じもの。
  test "同意書の画面にも同じヘッダーが出る" do
    Consent.delete_all
    visit "/s/#{@intake_session.raw_token}"

    assert_selector "h1", text: "メタトロン測定に関する同意"
    assert_selector "p.intake-meta", text: "会員No. #{@patient.karte_member_no}"
    assert_selector "p.intake-meta-sub", text: "生年月日：1985年3月4日（41歳） ／ 性別：女性"
  end

  private

  def open_questionnaire
    visit "/s/#{@intake_session.raw_token}"
    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'
  end

  def fill_and_send
    type_into_keyboard_pane("q1_purpose", "肩こりの相談")
    # 血液型は required で、この患者は users.blood_type が未設定のため聞かれる
    # （ask_unless: :blood_type_recorded?）。答えないと送信が止まる。
    # 副作用: 確定まで進むテストではこの患者の users.blood_type が
    # "unknown" になる。確定後のヘッダーを見るテストを足すときは
    # 「血液型：不明」が出ることを前提にすること。
    choose_radio("q0_blood_type", "unknown")
    choose_radio("q10_pacemaker", "no")
    # 【13】妊娠は female_only かつ必須。女性と判定された患者では
    # 答えないと送信が止まり、ヘッダーとは関係のないところで落ちる。
    choose_radio("q13_pregnant", "no")

    click_on "記入内容を送信する"
    assert_current_path intake_questionnaire_confirmation_path, wait: 10
    assert_selector '[data-signature-pad-target="canvas"]'
  end

  def type_into_keyboard_pane(key, text)
    scope = %([data-handwriting-field-key-value="#{key}"])
    find(%(#{scope} [data-handwriting-field-target="keyboardTab"])).click
    find(%(#{scope} [data-handwriting-field-target="textarea"])).fill_in(with: text)
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

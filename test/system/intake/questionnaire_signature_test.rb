require "application_system_test_case"

# 記入 → [送信] → 確認画面 → 署名 → 確定 を実ブラウザで通す。
#
# ── なぜ実ブラウザで見るのか ────────────────────────
#
# 確認画面と署名は Stimulus（questionnaire / signature-pad）で動く。
# サーバ側の境界（署名なしでは確定しない等）は
# test/integration/intake_questionnaire_signature_test.rb が見ているので、
# ここで見るのは「患者の操作でその境界に届くか」。
#   - [送信] で確認画面へ移れるか
#   - 署名するまで確定ボタンが押せないか
#   - 署名者名を消すと押せなくなるか
#   - 書き直しに戻って、下書きが残っているか
#
# ── 実機でしか確かめられないこと・重要 ──────────────────
#
# 署名 canvas は「幅が確定してから測り直す」仕組み
# （signature_pad_controller#resize + ResizeObserver）に頼っている。
# ヘッドレス Chrome はレイアウトが即座に確定するため、
# 待ち合わせが壊れていてもここは緑のままになる。
# 実際 staging の iPhone では「指でなぞっても線が出ない」を踏んでいる。
#
# 確認画面は同意書ページより上に長い内容（回答一覧・人体図）が積まれるので、
# 署名欄のレイアウト確定は同意書ページより遅れる。条件としては悪い側。
# この画面を触ったら、必ず iPad / iPhone 実機で
# 「開いた直後に指でなぞって線が出るか」を確かめること。
class Intake::QuestionnaireSignatureTest < ApplicationSystemTestCase
  setup do
    @original_app_host = Capybara.app_host
    @original_include_port = Capybara.always_include_port
    Capybara.always_include_port = true
    Capybara.app_host = "http://intake.localhost"

    document = ConsentDocument.create!(
      version: "q-signature-system-test", title: "同意書", body: "本文",
      published_at: Time.current
    )
    issuer = User.create!(email: "issuer-qsig@example.com", name: "発行者", password: "password")

    # gender を埋めておく。未設定だと冒頭で性別を聞かれ、
    # 【13】妊娠中ですか（female_only かつ必須）の出し分けも絡んで、
    # このテストが見たいものと関係のないところで送信が止まる。
    @patient = User.create!(email: "patient-qsig@example.com", name: "患者 太郎",
                            password: "password", gender: "m")
    Consent.create!(
      user: @patient, consent_document: document, agreed_at: Time.current,
      signer_name: "患者 太郎", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
    @intake_session = IntakeSession.issue!(patient: @patient, issuer: issuer)
  end

  teardown do
    Capybara.app_host = @original_app_host
    Capybara.always_include_port = @original_include_port
  end

  test "記入した内容が確認画面に出て、署名すると確定する" do
    fill_and_send

    assert_selector "h1", text: "記入内容のご確認"
    assert_text "肩こりの相談"
    assert_text "既婚"
    assert_text "記入内容に相違ないことを確認しました"

    assert questionnaire.status_draft?, "署名前に確定しています"

    sign_and_confirm
    wait_for_path intake_thanks_path
    assert_text "ありがとうございました"

    questionnaire.reload
    assert questionnaire.status_submitted?
    assert_equal "患者 太郎", questionnaire.signer_name
    assert questionnaire.signer_self_signed?
    assert_not_nil questionnaire.signed_at

    points = questionnaire.signature_strokes.first["points"]
    assert points.all? { |p| p["time"].present? },
           "time が落ちている。筆速・筆順が復元できず、模倣の検出力が失われる"
    assert questionnaire.signature_image.attached?, "署名画像が添付されていません"
  end

  test "署名するまで確定できない" do
    fill_and_send

    assert find(submit_selector).disabled?, "署名前に確定できてしまいます"
    assert_selector '[data-signature-pad-target="status"]', text: "ご署名いただくと送信できます。"

    draw_signature

    assert_not find(submit_selector).disabled?, "署名しても確定できません"
  end

  # 家族が代筆したときに「別人の署名だ」と誤判定されるのを防ぐため、
  # 署名者名は必ず要る。空のまま確定させない。
  test "署名者名を消すと確定できない" do
    fill_and_send
    draw_signature
    assert_not find(submit_selector).disabled?, "前提: 署名すれば押せること"

    find(".intake-field input[type=text]").fill_in(with: "")

    assert find(submit_selector).disabled?, "署名者名が空でも確定できてしまいます"
    assert_selector '[data-signature-pad-target="status"]',
                    text: "ご署名される方のお名前をご入力ください。"
  end

  test "代理人を選ぶと代理人として記録される" do
    fill_and_send
    find('input[value="guardian"]').click
    find(".intake-field input[type=text]").fill_in(with: "患者 花子")

    sign_and_confirm
    wait_for_path intake_thanks_path

    questionnaire.reload
    assert questionnaire.signer_guardian?
    assert_equal "患者 花子", questionnaire.signer_name
  end

  # 間違いに気づいたときに、署名してから直すのでは意味がない。
  test "確認画面から書き直しに戻れて、記入内容が残っている" do
    fill_and_send

    click_on "内容を書き直す"

    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'
    assert_equal "married", checked_value("q7_marital_status"),
                 "戻ったら書き直しになるのでは、間違いに気づいても直せない"
    assert questionnaire.status_draft?
  end

  private

  def submit_selector = '[data-signature-pad-target="submit"]'

  def questionnaire
    @patient.medical_questionnaires.sole
  end

  # 記入して [送信]。確認画面が出るまで待つ。
  def fill_and_send
    visit "/s/#{@intake_session.raw_token}"
    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'

    type_into_keyboard_pane("q1_purpose", "肩こりの相談")
    choose_radio("q7_marital_status", "married")
    choose_radio("q10_pacemaker", "no")

    click_on "記入内容を送信する"
    wait_for_path intake_questionnaire_confirmation_path
    assert_selector '[data-signature-pad-target="canvas"]'
  end

  # 画面遷移そのものを先に待つ。
  #
  # 遷移中に assert_text / find を回すと、Capybara が拾った DOM ノードが
  # 検査している最中に差し替わり、"Node with given id does not belong to
  # the document" で落ちる。要素を見るのは行き先が確定してからにする。
  def wait_for_path(path)
    assert_current_path path, wait: 10
  end

  def sign_and_confirm
    draw_signature
    click_on "上記の内容で確定する"
  end

  def type_into_keyboard_pane(key, text)
    scope = %([data-handwriting-field-key-value="#{key}"])
    find(%(#{scope} [data-handwriting-field-target="keyboardTab"])).click
    find(%(#{scope} [data-handwriting-field-target="textarea"])).fill_in(with: text)
  end

  def choose_radio(key, value)
    find(%(input[name="answers[#{key}]"][value="#{value}"])).click
  end

  def checked_value(key)
    find(%(input[name="answers[#{key}]"]:checked), visible: :all).value
  end

  def draw_signature
    canvas = find('[data-signature-pad-target="canvas"]')
    page.driver.browser.action
        .move_to(canvas.native, 10, 10)
        .click_and_hold.move_by(40, 20).move_by(40, -10).release.perform
    wait_until { stroke_count > 0 }
  end

  def stroke_count
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller="signature-pad"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'signature-pad');
        return ctrl ? ctrl.pad.toData().length : -1;
      })()
    JS
  end

  def wait_until(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    false
  end
end

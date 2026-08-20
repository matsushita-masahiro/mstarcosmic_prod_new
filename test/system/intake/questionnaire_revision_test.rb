require "application_system_test_case"

# 修正用QRで開いたとき、前版の内容が入った状態でフォームが出ることを守る。
#
# ── なぜ実ブラウザで測るのか ────────────────────────
#
# 前版は ERB で各 input に埋めておらず、localStorage と同じ形の JSON を
# 1箇所に渡して JS 側で描き直している（A-2 の経路にそのまま乗せた）。
# 描けたかどうかはリクエストテストでは見えない。
#
# ── localStorage との優先順位 ──────────────────────
#
# 復元は「端末優先、無ければサーバ」のまま変えていない。
# 代わりに訂正では storageKey を分けてある
# （初回 intake_draft_<患者ID> / 訂正 intake_revision_<前版ID>）。
# 既定のキーは患者ごとで来店ごとではないため、同じキーを使うと
# 初回記入時の書きかけが端末に残っていて、前版より優先されてしまう。
#
# 【このテストで捕まえられないこと・重要】
# 7本目と同じく、Stimulus が親（questionnaire）の connect() を
# 子（handwriting-field / body-map）より先に走らせる競合は
# ヘッドレス Chrome では再現しない（パースと接続が速いため）。
# 訂正画面も同じ restoreWhenReady() を通るので、ここが緑でも
# 「子の接続が間に合っている限り正しい」ことしか言えない。
# 訂正は別端末で開く前提の機能なので、必ず iPhone 実機で確認すること。
#
# 【canvas 幅の安全策について】
# 別端末で開くと canvas がせまく、復元した筆跡の右端が切れうる。
# 切れた canvas から作った PNG を送らないようにしてある。
# ヘッドレスでは幅が変わらないので、幅の違いは JS を直接叩いて作る。
class Intake::QuestionnaireRevisionTest < ApplicationSystemTestCase
  STROKES = [ {
    "penColor" => "#111827", "dotSize" => 0, "minWidth" => 0.6, "maxWidth" => 2.2,
    "velocityFilterWeight" => 0.7, "compositeOperation" => "source-over",
    "points" => [
      { "time" => 1_787_230_336_819, "x" => 40, "y" => 30, "pressure" => 0.5 },
      { "time" => 1_787_230_336_829, "x" => 90, "y" => 55, "pressure" => 0.5 },
      { "time" => 1_787_230_337_087, "x" => 140, "y" => 40, "pressure" => 0.5 }
    ]
  } ].freeze

  setup do
    @original_app_host = Capybara.app_host
    @original_include_port = Capybara.always_include_port
    Capybara.always_include_port = true
    Capybara.app_host = "http://intake.localhost"

    document = ConsentDocument.create!(
      version: "revision-system-test", title: "同意書", body: "本文", published_at: Time.current
    )
    @issuer  = User.create!(email: "issuer-rev-sys@example.com", name: "発行者", password: "password")
    @patient = User.create!(email: "patient-rev-sys@example.com", name: "患者", password: "password")
    Consent.create!(
      user: @patient, consent_document: document, agreed_at: Time.current,
      signer_name: "患者", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
    @previous = create_previous_version
  end

  teardown do
    Capybara.app_host = @original_app_host
    Capybara.always_include_port = @original_include_port
  end

  # 本丸。4種すべてが前版から戻ること。
  test "修正用QRで開くと前版の内容が入っている" do
    open_revision

    assert_equal "married", checked_answer("q7_marital_status"),
                 "前版の回答が入っていません"
    assert_operator stroke_count("q1_purpose"), :>, 0,
                    "前版のペン手書きが入っていません"
    assert_equal "五十肩で通院していました", textarea_value("q3_history"),
                 "前版のキーボード入力が入っていません"
    assert_equal 1, body_mark_count, "前版の人体図が入っていません"
  end

  test "修正であることが画面に出ている" do
    open_revision

    assert_text "問診票の修正"
    assert_text "変更するところだけ直して"
    assert_text "前の記録はそのまま残ります"
  end

  # 既定のキーは患者ごとで来店ごとではないため、初回の書きかけが端末に残る。
  # 同じキーを使うと、前版ではなくその書きかけが復元されてしまう。
  test "初回記入の下書きが端末に残っていても前版が優先される" do
    seed_initial_local_draft("初回に書きかけた内容")

    open_revision

    assert_equal "五十肩で通院していました", textarea_value("q3_history"),
                 "端末に残っていた初回の下書きが前版より優先されています"
  end

  test "訂正の下書きは初回とは別のキーに保存される" do
    seed_initial_local_draft("初回に書きかけた内容")
    open_revision

    type_into_keyboard_pane("q3_history", "訂正で書き直した内容")
    assert wait_until { local_draft_text(revision_key, "q3_history") == "訂正で書き直した内容" },
           "訂正の下書きが専用のキーに保存されていません"

    assert_equal "初回に書きかけた内容", local_draft_text(initial_key, "q3_history"),
                 "初回の下書きを壊しています"
  end

  test "訂正を書きかけて開き直すと、前版ではなく書きかけが出る" do
    open_revision
    type_into_keyboard_pane("q3_history", "訂正で書き直した内容")
    assert wait_until { local_draft_text(revision_key, "q3_history") == "訂正で書き直した内容" }

    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q3_history"]'

    assert_equal "訂正で書き直した内容", textarea_value("q3_history"),
                 "書きかけが前版で上書きされています"
  end

  # ── canvas 幅の安全策 ──────────────────────────

  test "同じ幅なら従来どおり PNG を送る" do
    open_revision

    assert serialized_has_image?("q1_purpose"),
           "幅が同じなのに PNG が送られなくなっています"
  end

  test "復元元よりせまい canvas では PNG を送らない" do
    open_revision
    shrink_canvas("q1_purpose")

    assert_not serialized_has_image?("q1_purpose"),
               "切れた canvas から作った PNG が送られます（カルテの画像が欠けます）"
    assert_operator serialized_stroke_count("q1_purpose"), :>, 0,
                    "strokes まで落ちています（情報が失われます）"
  end

  # 「消す」で書き直したら、復元元の幅とは無関係になる。
  # ここが外れると、一度復元した欄は書き直しても PNG が付かないままになる。
  test "消して書き直した欄は幅の判定を受けなくなる" do
    open_revision
    clear_field("q1_purpose")
    use_pen("q1_purpose")
    wait_until { canvas_width("q1_purpose") > 0 }
    draw_on("q1_purpose")

    assert_nil restored_width("q1_purpose"),
               "書き直したのに復元元の幅を持ったままです"
    assert serialized_has_image?("q1_purpose"),
           "書き直した欄まで PNG が落ちています"
  end

  private

  def create_previous_version
    questionnaire = @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, status: :submitted,
      submitted_at: 3.days.ago, answers: { "q7_marital_status" => "married" }
    )
    questionnaire.handwriting_entries.create!(
      question_key: "q1_purpose", input_mode: :pen, strokes: STROKES,
      canvas_width: 860, canvas_height: 140
    )
    questionnaire.handwriting_entries.create!(
      question_key: "q3_history", input_mode: :keyboard,
      transcribed_text: "五十肩で通院していました"
    )
    questionnaire.body_marks.create!(side: :front, x: 0.4, y: 0.3, mark_type: :pain)
    questionnaire
  end

  def open_revision
    record = IntakeSession.issue_revision!(patient: @patient, issuer: @issuer, target: @previous)
    visit "/s/#{record.raw_token}"
    assert_selector '[data-handwriting-field-key-value="q3_history"]'
  end

  def initial_key  = "intake_draft_#{@patient.id}"
  def revision_key = "intake_revision_#{@previous.id}"

  # 初回記入の下書きを端末に置く。訂正で開いたときに拾われないことを見る。
  def seed_initial_local_draft(text)
    record = IntakeSession.issue!(patient: @patient, issuer: @issuer)
    visit "/s/#{record.raw_token}"
    visit "/expired"
    page.execute_script(<<~JS)
      localStorage.setItem('#{initial_key}', JSON.stringify({
        savedAt: Date.now(),
        answers: {},
        handwriting: { q3_history: { mode: "keyboard", text: #{text.to_json} } },
        bodyMarks: []
      }))
    JS
  end

  def local_draft_text(key, field)
    page.evaluate_script(<<~JS)
      (() => {
        const raw = localStorage.getItem('#{key}');
        if (!raw) return null;
        return JSON.parse(raw).handwriting?.['#{field}']?.text ?? null;
      })()
    JS
  end

  def field_script(key) = %([data-handwriting-field-key-value="#{key}"])

  def textarea_value(key)
    find(%(#{field_script(key)} [data-handwriting-field-target="textarea"]), visible: :all).value
  end

  def type_into_keyboard_pane(key, text)
    find(%(#{field_script(key)} [data-handwriting-field-target="keyboardTab"])).click
    find(%(#{field_script(key)} [data-handwriting-field-target="textarea"])).fill_in(with: text)
  end

  def use_pen(key)
    find(%(#{field_script(key)} [data-handwriting-field-target="penTab"])).click
  end

  def clear_field(key)
    find(%(#{field_script(key)} [data-action~="handwriting-field#clear"])).click
  end

  def checked_answer(key)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[name="answers[#{key}]"]:checked');
        return el ? el.value : null;
      })()
    JS
  end

  def body_mark_count
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="body-map"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'body-map');
        return ctrl ? ctrl.marks.length : -1;
      })()
    JS
  end

  def canvas_width(key)
    page.evaluate_script(<<~JS)
      (() => {
        const c = document.querySelector('#{field_script(key)} [data-handwriting-field-target="canvas"]');
        return c ? c.width : -1;
      })()
    JS
  end

  def stroke_count(key)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('#{field_script(key)}');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'handwriting-field');
        return ctrl && ctrl.pad ? ctrl.pad.toData().length : -1;
      })()
    JS
  end

  def draw_on(key)
    canvas = find(%(#{field_script(key)} [data-handwriting-field-target="canvas"]))
    page.driver.browser.action
        .move_to(canvas.native, 10, 10)
        .click_and_hold.move_by(40, 15).move_by(30, -10).release.perform
    wait_until { stroke_count(key) > 0 }
  end

  # 別端末で開いた状況を作る。ヘッドレスでは画面幅が変わらないので、
  # 復元元として控えている幅を実際の canvas より広い値に差し替える。
  def shrink_canvas(key)
    page.execute_script(<<~JS)
      const el = document.querySelector('#{field_script(key)}');
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'handwriting-field');
      const rect = ctrl.canvasTarget.getBoundingClientRect();
      ctrl.restoredWidth = Math.round(rect.width * 2);
    JS
  end

  def restored_width(key)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('#{field_script(key)}');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'handwriting-field');
        return ctrl ? ctrl.restoredWidth : 'controller-missing';
      })()
    JS
  end

  def serialized(key)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('#{field_script(key)}');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'handwriting-field');
        const data = ctrl.serialize();
        if (!data) return null;
        return { hasImage: typeof data.image === 'string', strokes: (data.strokes || []).length };
      })()
    JS
  end

  def serialized_has_image?(key) = serialized(key)&.fetch("hasImage", false)
  def serialized_stroke_count(key) = serialized(key)&.fetch("strokes", -1) || -1

  def wait_until(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
    end
    false
  end
end

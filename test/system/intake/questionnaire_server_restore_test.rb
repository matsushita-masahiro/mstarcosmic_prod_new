require "application_system_test_case"

# 端末に下書きが残っていないとき、サーバの下書きが画面に戻ることを守るテスト。
#
# ── なぜ要るか ──────────────────────────────
#
# 以前 intake のフォームはサーバの下書きを一切描いていなかった
# （show の @questionnaire がどのビューからも参照されていなかった）。
# 復元経路が localStorage 単独で、そこが欠けると画面は空で戻り、
# 患者は最初から書き直しになる。
# 7本目で「復元に失敗しても記録は消さない」ようにしたが、
# 記録が残っていても画面に戻らなければ患者にとっては同じことだった。
#
# 訂正機能の前提でもある。前版を復元するのに localStorage は使えない
# （別セッション・別端末の可能性がある）。
#
# ── 優先順位（時刻比較を入れないこと）──────────────
#
# localStorage が優先。同じ端末で書き続けるのが主な使われ方で、
# その場合は端末のほうが常に新しい（最後の autosave が届いていない
# 最大30秒ぶんを持っている）。サーバは端末が使えなかったときの受け皿。
# savedAt と updated_at の比較は入れない。端末の時計がずれていると
# 誤判定するだけで得るものが無い。
#
# 【このテストで捕まえられないこと・重要】
# 7本目と同じく、Stimulus が親（questionnaire）の connect() を
# 子（handwriting-field / body-map）より先に走らせる競合は
# ヘッドレス Chrome では再現しない（パースと接続が速いため）。
# サーバ復元も同じ restoreWhenReady() を通るので、
# ここが緑でも「子の接続が間に合っている限り正しい」ことしか言えない。
# この経路を触ったら、必ず iPhone 実機で確認すること。
class Intake::QuestionnaireServerRestoreTest < ApplicationSystemTestCase
  # signature_pad の toData() が返す形。端末から届くものと同じ。
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
      version: "server-restore-system-test", title: "同意書", body: "本文",
      published_at: Time.current
    )
    issuer   = User.create!(email: "issuer-server-restore@example.com", name: "発行者", password: "password")
    @patient = User.create!(email: "patient-server-restore@example.com", name: "患者", password: "password")
    Consent.create!(
      user: @patient, consent_document: document, agreed_at: Time.current,
      signer_name: "患者", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
    @intake_session = IntakeSession.issue!(patient: @patient, issuer: issuer)
  end

  teardown do
    Capybara.app_host = @original_app_host
    Capybara.always_include_port = @original_include_port
  end

  # 本丸。4種すべてが戻ること。
  test "端末に何も残っていなくてもサーバの下書きから復元される" do
    create_server_draft

    open_questionnaire_without_local_draft

    assert_equal "married", checked_answer("q7_marital_status"),
                 "answers がサーバから復元されていません"
    assert_operator stroke_count("q1_purpose"), :>, 0,
                    "ペンの筆跡がサーバから復元されていません"
    assert_equal "五十肩で通院していました", textarea_value("q3_history"),
                 "キーボード入力がサーバから復元されていません"
    assert_equal 1, body_mark_count,
                 "人体図のマーカーがサーバから復元されていません"
  end

  # サーバから戻したときは「前回の続き」ではない（この端末には残っていなかった）。
  test "サーバから復元したときは端末を前提にしない文言が出る" do
    create_server_draft

    open_questionnaire_without_local_draft

    assert_equal "保存されていた記入内容を読み込みました", status_text
  end

  # ここが false のままだと autosave に partial が付き続け、
  # サーバは削除を一切しなくなる（患者が消した欄が残り続ける）。
  test "サーバから復元しても restoreVerified が true になる" do
    create_server_draft

    open_questionnaire_without_local_draft

    assert_equal true, restore_verified?,
                 "サーバ復元が verifyRestore() と噛み合っていません（partial が付いたままになります）"
  end

  test "端末に下書きがあればサーバより優先される" do
    create_server_draft
    seed_local_draft(text: "端末に残っていた新しい内容")

    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q3_history"]'

    assert_equal "端末に残っていた新しい内容", textarea_value("q3_history"),
                 "サーバの下書きが端末の下書きを上書きしています"
    assert_equal "前回の記入内容を復元しました", status_text
  end

  test "下書きが無ければ何も復元されず、属性も出ない" do
    open_questionnaire_without_local_draft

    assert page.has_no_css?("[data-questionnaire-server-draft-value]"),
           "下書きが無いのに空の下書きが埋め込まれています"
    assert_nil checked_answer("q7_marital_status")
    assert_equal "", textarea_value("q3_history")
    assert_equal "", status_text, "復元していないのに復元の案内が出ています"
  end

  # 空の下書き（レコードはあるが中身が無い）でも同じ。
  test "中身の無い下書きは埋め込まれない" do
    MedicalQuestionnaire.create!(
      user: @patient, intake_session: @intake_session, status: :draft,
      form_version: MedicalQuestionnaireForm::VERSION
    )

    open_questionnaire_without_local_draft

    assert page.has_no_css?("[data-questionnaire-server-draft-value]"),
           "中身の無い下書きが埋め込まれています"
    assert_equal "", status_text
  end

  private

  def create_server_draft
    questionnaire = MedicalQuestionnaire.create!(
      user: @patient, intake_session: @intake_session, status: :draft,
      form_version: MedicalQuestionnaireForm::VERSION,
      answers: { "q7_marital_status" => "married" }
    )
    questionnaire.handwriting_entries.create!(
      question_key: "q1_purpose", input_mode: :pen,
      strokes: STROKES, canvas_width: 860, canvas_height: 140
    )
    questionnaire.handwriting_entries.create!(
      question_key: "q3_history", input_mode: :keyboard,
      transcribed_text: "五十肩で通院していました"
    )
    # 中身の空いた欄をわざと混ぜる。
    # 端末側の collectHandwriting() は空欄のキーを落とすので、サーバの下書きが
    # これを含めると verifyRestore() が「戻らなかった欄」と数え、
    # restoreVerified が false のまま partial 付きの送信が続く。
    # この1件があることで、下の restoreVerified のテストが空振りしなくなる。
    questionnaire.handwriting_entries.create!(
      question_key: "q5_occupation", input_mode: :keyboard, transcribed_text: ""
    )
    questionnaire.body_marks.create!(side: :front, x: 0.4, y: 0.3, mark_type: :pain)
    questionnaire
  end

  # 端末に何も残っていない状態で問診票を開く。
  # /s/:token は同意画面へ飛ぶので、そこで localStorage を空にしてから移動する。
  def open_questionnaire_without_local_draft
    visit "/s/#{@intake_session.raw_token}"
    page.execute_script("localStorage.clear()")
    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q3_history"]'
  end

  # 端末側の下書きを直接置く。saveLocalDraft() が書くのと同じ形。
  def seed_local_draft(text:)
    visit "/s/#{@intake_session.raw_token}"
    page.execute_script(<<~JS)
      localStorage.setItem('intake_draft_#{@patient.id}', JSON.stringify({
        savedAt: Date.now(),
        answers: {},
        handwriting: { q3_history: { mode: "keyboard", text: #{text.to_json} } },
        bodyMarks: []
      }))
    JS
  end

  def field_script(key) = %([data-handwriting-field-key-value="#{key}"])

  def textarea_value(key)
    find(%(#{field_script(key)} [data-handwriting-field-target="textarea"]), visible: :all).value
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

  def restore_verified?
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="questionnaire"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'questionnaire');
        return ctrl ? ctrl.restoreVerified : null;
      })()
    JS
  end

  def status_text
    find('[data-questionnaire-target="status"]', visible: :all).text
  end
end

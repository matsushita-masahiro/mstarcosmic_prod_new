require "application_system_test_case"

# リロード後に記入内容が画面へ復元されることを守るテスト。
#
# ── なぜ重要か ────────────────────────────────
#
# 6本目（1c26119）で「届いたハッシュに含まれないキーは削除する」にしたため、
# 画面への復元が失敗すると、その直後の autosave が
# 「その欄は空になった」と判断してサーバからも消してしまう。
# 復元失敗が記録の消失に直結する。
#
# 【この経路の弱さ】
# intake のフォームはサーバの下書きを一切描かない（show の @questionnaire は
# ビューから参照されていない）。リロード時の復元は localStorage だけが頼りで、
# そこが欠けると画面は空で戻り、直後の autosave がサーバ側も消す。
# ここが緑でも「localStorage が生きている限り正しい」ことしか言えない。
class Intake::QuestionnaireRestoreTest < ApplicationSystemTestCase
  setup do
    @original_app_host = Capybara.app_host
    @original_include_port = Capybara.always_include_port
    Capybara.always_include_port = true
    Capybara.app_host = "http://intake.localhost"

    document = ConsentDocument.create!(
      version: "restore-system-test", title: "同意書", body: "本文",
      published_at: Time.current
    )
    issuer   = User.create!(email: "issuer-restore@example.com", name: "発行者", password: "password")
    @patient = User.create!(email: "patient-restore@example.com", name: "患者", password: "password")
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

  test "ペンで書いた筆跡がリロード後に復元される" do
    visit_questionnaire
    use_pen("q1_purpose")
    wait_until { canvas_width("q1_purpose") > 0 }
    draw_on("q1_purpose")
    before = stroke_count("q1_purpose")
    assert_operator before, :>, 0, "前提: 書けていること"

    trigger_autosave
    assert wait_until { local_draft_has?("q1_purpose") }, "前提: localStorage に入ること"

    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'

    assert_operator stroke_count("q1_purpose"), :>, 0,
                    "リロード後にペンの筆跡が復元されていません"
  end

  test "キーボードで書いた内容がリロード後に復元される" do
    visit_questionnaire
    type_into_keyboard_pane("q1_purpose", "リロードしても残る内容")
    trigger_autosave
    assert wait_until { local_draft_has?("q1_purpose") }

    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'

    assert_equal "リロードしても残る内容", textarea_value("q1_purpose"),
                 "リロード後にキーボード入力が復元されていません"
  end

  test "復元後に自動保存が走ってもサーバから消えない" do
    visit_questionnaire
    use_pen("q1_purpose")
    wait_until { canvas_width("q1_purpose") > 0 }
    draw_on("q1_purpose")
    trigger_autosave
    assert wait_until { draft&.handwriting_entries&.any? }, "前提: サーバに届くこと"

    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'
    trigger_autosave

    sleep 1
    assert draft&.handwriting_entries&.any?,
           "復元に失敗した状態で autosave が走り、サーバから消えています"
  end

  private

  def visit_questionnaire
    visit "/s/#{@intake_session.raw_token}"
    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'
  end

  def draft
    @patient.medical_questionnaires.status_draft.first
  end

  def field_script(key) = %([data-handwriting-field-key-value="#{key}"])

  def use_pen(key)
    find(%(#{field_script(key)} [data-handwriting-field-target="penTab"])).click
  end

  def type_into_keyboard_pane(key, text)
    find(%(#{field_script(key)} [data-handwriting-field-target="keyboardTab"])).click
    find(%(#{field_script(key)} [data-handwriting-field-target="textarea"])).fill_in(with: text)
  end

  def textarea_value(key)
    find(%(#{field_script(key)} [data-handwriting-field-target="textarea"]), visible: :all).value
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

  def local_draft_has?(key)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="questionnaire"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'questionnaire');
        if (!ctrl) return false;
        const raw = localStorage.getItem(ctrl.storageKeyValue);
        if (!raw) return false;
        return !!JSON.parse(raw).handwriting?.['#{key}'];
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

  def trigger_autosave
    page.execute_script(<<~JS)
      const el = document.querySelector('[data-controller~="questionnaire"]');
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'questionnaire');
      ctrl.dirty = true;
      ctrl.autosave();
    JS
  end

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

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
# 【このテストで捕まえられないこと・重要】
# Stimulus が親（questionnaire）の connect() を子（handwriting-field / body-map）
# より先に走らせる競合は、ヘッドレス Chrome では再現しない。
# パースと接続が速く、親が動く時点で子が既に揃っているため。
# iPhone 実機では発生し、手書き・人体図だけが復元されない
# （answers は DOM への直接代入なので成功し、「復元しました」も出る）。
#
# つまり以下が緑でも「子の接続が間に合っている限り正しい」ことしか言えない。
# restoreWhenReady() の待ち合わせが効いているかは実機でしか確かめられない。
# この経路を触ったら、必ず実機で確認すること。
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

  # localStorage への保存は通信を伴わないので、autosave（30秒）に律する理由がない。
  # 以前は autosave の中でしか呼ばれておらず、次の autosave までに端末が落ちると
  # 直前30秒ぶんの記入が失われていた。
  test "自動保存を待たずに、入力直後のリロードで内容が復元される" do
    visit_questionnaire

    type_into_keyboard_pane("q1_purpose", "30秒待たずに残る内容")

    # autosave は走らせない。localStorage に落ちたことだけを待つ。
    assert wait_until { local_draft_has?("q1_purpose") },
           "入力しても localStorage に保存されていません（30秒ごとのままです）"
    assert_nil draft, "前提: この時点ではサーバにはまだ何も送っていないこと"

    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'

    assert_equal "30秒待たずに残る内容", textarea_value("q1_purpose"),
                 "自動保存前の入力がリロードで失われています"
  end

  test "ペンの筆跡も自動保存を待たずに localStorage へ落ちる" do
    visit_questionnaire
    use_pen("q1_purpose")
    wait_until { canvas_width("q1_purpose") > 0 }
    draw_on("q1_purpose")

    assert wait_until { local_draft_has?("q1_purpose") },
           "手書き後に localStorage へ保存されていません"

    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'
    assert_operator stroke_count("q1_purpose"), :>, 0,
                    "自動保存前の筆跡がリロードで失われています"
  end

  # Stimulus の接続順そのものは再現できないが、待ち合わせの仕組みは検証できる。
  # handwritingControllers() を「最初の数回は空を返す」に差し替え、
  # 子が遅れて接続する状況を作る。待たない実装ではここで復元が空振りする。
  test "子コントローラの接続が遅れても復元される" do
    visit_questionnaire
    type_into_keyboard_pane("q1_purpose", "遅れて接続しても戻る内容")
    assert wait_until { local_draft_has?("q1_purpose") }

    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'

    # 画面を空にしてから、子が遅れて接続する状況で復元をやり直させる
    delayed_restore(empty_calls: 4)

    assert wait_until { textarea_value("q1_purpose") == "遅れて接続しても戻る内容" },
           "子の接続を待たずに復元し、内容が戻っていません"
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

  # 子コントローラが empty_calls 回ぶん「まだ接続していない」状況を作り、
  # 画面を空にしたうえで復元をやり直させる。
  def delayed_restore(empty_calls:)
    page.execute_script(<<~JS)
      const el = document.querySelector('[data-controller~="questionnaire"]');
      const c = window.Stimulus.getControllerForElementAndIdentifier(el, 'questionnaire');

      document.querySelectorAll('[data-handwriting-field-target="textarea"]')
              .forEach((t) => { t.value = ""; });

      const real = c.handwritingControllers.bind(c);
      let calls = 0;
      c.handwritingControllers = () => (++calls <= #{empty_calls} ? [] : real());

      c.restored = false;
      c.restoreWhenReady();
    JS
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

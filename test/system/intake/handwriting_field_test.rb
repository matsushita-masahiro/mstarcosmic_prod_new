require "application_system_test_case"

# 問診票の手書き欄が 0×0 で確定しないことの回帰テスト。
#
# 署名 canvas と同じ問題を踏みうる。こちらは条件付き表示があるぶん厄介で、
# 【17】のサブ項目は「はい」を選ぶまで hidden なので connect 時の幅は必ず 0 になる。
# 幅0のときに測ってしまうと、後から表示しても 0×0 のままで書けない。
#
# 落ちたときは handwriting_field_controller#resize の「幅0ならスキップ」と
# ResizeObserver の登録を先に疑うこと。
#
# 【既定モードについて】
# 欄はキーボードで開くため、ペンの canvas は最初 hidden で幅0になる。
# 各テストは手書きタブを押してから測る。押した直後に測り直されることまで
# 含めて、ここが守っている範囲。
class Intake::HandwritingFieldTest < ApplicationSystemTestCase
  setup do
    @original_app_host = Capybara.app_host
    @original_include_port = Capybara.always_include_port
    Capybara.always_include_port = true
    Capybara.app_host = "http://intake.localhost"

    document = ConsentDocument.create!(
      version: "handwriting-system-test", title: "同意書", body: "本文",
      published_at: Time.current
    )
    issuer  = User.create!(email: "issuer-hw@example.com", name: "発行者", password: "password")
    @patient = User.create!(email: "patient-hw@example.com", name: "患者", password: "password")
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

  # 既定はキーボード。実運用ではキーボードで書く患者が多数のため。
  # ペンで書かれた欄の復元は restore() が保存データの mode を見るので、
  # この既定には左右されない。
  test "手書き欄はキーボードペインで開く" do
    visit_questionnaire

    assert pane_hidden?("q1_purpose", "penPane"), "既定でペンのペインが開いています"
    assert_not pane_hidden?("q1_purpose", "keyboardPane"),
               "既定でキーボードのペインが閉じています"
    assert tab_active?("q1_purpose", "keyboardTab"),
           "キーボードのタブが選択状態になっていません"
  end

  test "手書きタブを押した直後の欄に描ける" do
    visit_questionnaire

    # 【1】ご来院の目的
    use_pen("q1_purpose")
    wait_until { canvas_width("q1_purpose") > 0 }
    assert_operator canvas_width("q1_purpose"), :>, 0,
                    "【1】の canvas が 0×0 です（タブ切替後に測り直されていない）"

    draw_on("q1_purpose")
    assert_operator stroke_count("q1_purpose"), :>, 0, "【1】に線が引けること"
  end

  test "【17】で「はい」に切り替えた直後の手書き欄にも描ける" do
    visit_questionnaire

    # 切り替える前は hidden なので幅0のまま（ここで測ると 0×0 で固まる）
    assert_equal 0, css_width("q17_removed_organ"),
                 "「はい」を選ぶ前は非表示のはず"

    choose_yes("q17_has_additional")
    use_pen("q17_removed_organ")

    # 表示された時点で ResizeObserver / conditional-field が測り直す
    wait_until { canvas_width("q17_removed_organ") > 0 }
    assert_operator canvas_width("q17_removed_organ"), :>, 0,
                    "【17】のサブ項目が 0×0 のままです（表示後に測り直されていない）"

    draw_on("q17_removed_organ")
    assert_operator stroke_count("q17_removed_organ"), :>, 0,
                    "表示直後の【17】サブ項目に線が引けること"
  end

  test "「いいえ」に戻してから「はい」にしても描ける" do
    visit_questionnaire

    choose_yes("q17_has_additional")
    use_pen("q17_removed_organ")
    wait_until { canvas_width("q17_removed_organ") > 0 }

    choose_no("q17_has_additional")
    choose_yes("q17_has_additional")
    use_pen("q17_removed_organ")

    wait_until { canvas_width("q17_removed_organ") > 0 }
    draw_on("q17_removed_organ")
    assert_operator stroke_count("q17_removed_organ"), :>, 0,
                    "出し入れを繰り返した後も線が引けること"
  end

  private

  def visit_questionnaire
    visit "/s/#{@intake_session.raw_token}"
    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'
  end

  def field_script(key)
    %([data-handwriting-field-key-value="#{key}"])
  end

  # 手書きタブに切り替える。既定がキーボードなので、ペンを測る前に必ず押す。
  def use_pen(key)
    find(%(#{field_script(key)} [data-handwriting-field-target="penTab"])).click
  end

  def pane_hidden?(key, target)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('#{field_script(key)} [data-handwriting-field-target="#{target}"]');
        return el ? el.hidden : null;
      })()
    JS
  end

  def tab_active?(key, target)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('#{field_script(key)} [data-handwriting-field-target="#{target}"]');
        return el ? el.classList.contains('is-active') : null;
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

  def css_width(key)
    page.evaluate_script(<<~JS)
      (() => {
        const c = document.querySelector('#{field_script(key)} [data-handwriting-field-target="canvas"]');
        return c ? c.getBoundingClientRect().width : -1;
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
        .click_and_hold
        .move_by(40, 15)
        .move_by(30, -10)
        .release
        .perform
    wait_until { stroke_count(key) > 0 }
  end

  def choose_yes(key) = choose_value(key, "yes")
  def choose_no(key)  = choose_value(key, "no")

  def choose_value(key, value)
    find(%(input[name="answers[#{key}]"][value="#{value}"]), visible: :all).click
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

require "application_system_test_case"

# 同意書の署名 canvas が 0×0 で確定してしまう不具合の回帰テスト。
#
# 症状: staging の iPhone で同意書に署名できない。
# 原因: connect 時に getBoundingClientRect().width が 0 の状態で resize() が走り、
#       canvas が 0×0 のまま確定していた。指でなぞっても線が出ない。
#       画面回転やアドレスバーの伸縮で resize イベントが飛ぶと測り直されるため、
#       「スクロールしたら書けた」ように見えていた。
#
# ここで押さえるのは2点。
#   - 開いた直後に canvas が 0×0 になっていないこと
#   - 幅0で connect しても、幅が確定した時点で ResizeObserver が測り直すこと
#
# 落ちたときは signature_pad_controller#resize の
# 「幅0ならスキップ」と ResizeObserver の登録を先に疑うこと。
class Intake::SignaturePadTest < ApplicationSystemTestCase
  setup do
    @original_app_host = Capybara.app_host
    @original_include_port = Capybara.always_include_port
    Capybara.always_include_port = true
    Capybara.app_host = "http://intake.localhost"

    ConsentDocument.create!(
      version: "signature-system-test", title: "同意書",
      # 本文が長いほどレイアウト確定が遅れる。実際の同意書に寄せる。
      body: "同意事項\n" + ("本文の行。" * 40 + "\n") * 40,
      published_at: Time.current
    )
    issuer  = User.create!(email: "issuer-sig@example.com", name: "発行者", password: "password")
    patient = User.create!(email: "patient-sig@example.com", name: "患者", password: "password")

    # 同意書ページを出したいので Consent は作らない
    @intake_session = IntakeSession.issue!(patient: patient, issuer: issuer)
  end

  teardown do
    Capybara.app_host = @original_app_host
    Capybara.always_include_port = @original_include_port
  end

  test "開いた直後に署名 canvas が 0×0 になっていない" do
    visit_consent

    size = canvas_size
    assert_operator size["width"], :>, 0, "canvas の実ピクセル幅が 0 です（0×0 で確定している）"
    assert_operator size["height"], :>, 0, "canvas の実ピクセル高さが 0 です"

    # CSS 上の表示幅と実ピクセル幅が devicePixelRatio 倍で対応していること
    assert_operator size["width"], :>=, size["cssWidth"],
                    "実ピクセル幅が表示幅を下回っています（DPR のスケールが効いていない）"
  end

  test "幅0で connect しても、幅が確定した時点で測り直される" do
    visit_consent

    # 幅0のまま connect させる。
    # 要素を display:none の親へ移すと Stimulus が disconnect → connect し直すため、
    # 「レイアウト確定前に connect した」状態を再現できる。
    page.execute_script(<<~JS)
      const el = document.querySelector('[data-controller="signature-pad"]');
      const canvas = el.querySelector('[data-signature-pad-target="canvas"]');
      canvas.width = 0;
      canvas.height = 0;

      const box = document.createElement('div');
      box.id = 'reconnect-box';
      box.style.display = 'none';
      el.parentNode.insertBefore(box, el);
      box.appendChild(el);
    JS

    # 隠れている間は測り直さない（0×0 で確定させない）
    wait_until { canvas_size["width"].zero? }
    assert_equal 0, canvas_size["width"], "幅0のときに測ってしまっています"

    # 幅が確定した時点で ResizeObserver が拾って測り直す
    page.execute_script("document.getElementById('reconnect-box').style.display = 'block';")

    wait_until { canvas_size["width"] > 0 }
    assert_operator canvas_size["width"], :>, 0,
                    "幅が確定しても測り直されていません（ResizeObserver が効いていない）"
  end

  # 測り終わった後に非表示になっても 0×0 で潰さないこと。
  #
  # connect 直後に幅0で測ってしまう分は lastWidth の初期値0に吸収されるが、
  # 一度測った後に非表示になると ResizeObserver が 0 を通知してくる。
  # ここで測り直すと canvas が 0×0 になり、再表示しても幅が変わらないため
  # ResizeObserver も動かず、書けないまま戻らなくなる。
  test "測った後に非表示になっても 0×0 で潰さない" do
    visit_consent

    measured = canvas_size["width"]
    assert_operator measured, :>, 0

    page.execute_script(<<~JS)
      const el = document.querySelector('[data-controller="signature-pad"]');
      el.style.display = 'none';
    JS

    # ResizeObserver が 0 を通知してくるのを待つ
    wait_until { canvas_size["width"] != measured }

    assert_equal measured, canvas_size["width"],
                 "非表示になった時点で測り直しており、canvas が 0×0 になっています"

    # 再表示すれば元どおり書ける状態に戻る
    page.execute_script("document.querySelector('[data-controller=\"signature-pad\"]').style.display = '';")
    wait_until { canvas_size["cssWidth"] > 0 }
    assert_operator canvas_size["width"], :>, 0
  end

  test "署名前は案内が出て、描くと消えて送信できるようになる" do
    visit_consent

    assert_selector '[data-signature-pad-target="status"]', text: "ご署名いただくと送信できます。"
    assert find('[data-signature-pad-target="submit"]').disabled?, "署名前は送信できないこと"

    draw_on_canvas

    assert_selector '[data-signature-pad-target="status"]', text: ""
    assert_not find('[data-signature-pad-target="submit"]').disabled?, "署名後は送信できること"
  end

  test "描いた後に幅が変わっても線が消えない" do
    visit_consent
    draw_on_canvas

    before = stroke_count
    assert_operator before, :>, 0, "ストロークが記録されていること"

    # 画面回転やアドレスバーの伸縮に相当する幅の変化
    page.execute_script("document.querySelector('.intake-shell').style.maxWidth = '600px';")
    wait_until { canvas_size["cssWidth"] < 900 }

    assert_equal before, stroke_count, "測り直しでストロークが消えています"
  end

  private

  def visit_consent
    visit "/s/#{@intake_session.raw_token}"
    assert_selector '[data-signature-pad-target="canvas"]'
  end

  def canvas_size
    page.evaluate_script(<<~JS)
      (() => {
        const c = document.querySelector('[data-signature-pad-target="canvas"]');
        const r = c.getBoundingClientRect();
        return { width: c.width, height: c.height, cssWidth: r.width };
      })()
    JS
  end

  # SignaturePad が記録しているストローク数
  def stroke_count
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller="signature-pad"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'signature-pad');
        return ctrl ? ctrl.pad.toData().length : -1;
      })()
    JS
  end

  def draw_on_canvas
    canvas = find('[data-signature-pad-target="canvas"]')
    page.driver.browser.action
        .move_to(canvas.native, 10, 10)
        .click_and_hold
        .move_by(40, 20)
        .move_by(40, -10)
        .release
        .perform
    wait_until { stroke_count > 0 }
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

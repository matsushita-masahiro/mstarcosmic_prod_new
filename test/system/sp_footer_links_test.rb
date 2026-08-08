require "application_system_test_case"

# スマホのフッターのナビリンク（#sp-footer-links）。
#
# 792px 以下では #footer が display:none になり #sp-footer に入れ替わるが、
# #sp-footer にはロゴとページトップしか無く、スマホからプライバシーポリシーへ
# 到達する導線が存在しなかった。それを埋めるのが #sp-footer-links。
#
# PC 側で #sp-footer-links { display: none } としているため、
# スマホ側で display を戻し忘れると「CSS が効かずリンクが出ない」状態になる。
# 見た目が変わらないので目視では見落とす。以下はその退行を止めるためのテスト。
class SpFooterLinksTest < ApplicationSystemTestCase
  # PC 側と同じ5項目（#footer .footer-middle と対応）
  EXPECTED_LINKS = {
    "HOME" => "/",
    "メタトロンとは" => "/about_metatron",
    "料金表" => "/price_plan",
    "サロンHPについて" => "/lppage",
    "プライバシーポリシー" => "/privacy"
  }.freeze

  # headless chrome の window.resize_to はウィンドウ枠の分だけ大きくなり、
  # 幅 500px 未満に絞れない。実幅で検証するため CDP で viewport を上書きする。
  def set_viewport(width, height)
    page.driver.browser.execute_cdp(
      "Emulation.setDeviceMetricsOverride",
      width: width, height: height, deviceScaleFactor: 1, mobile: true
    )
  end

  # 条件が満たされるまで待つ。満たされなければ Timeout::Error で落とす。
  def wait_until(message)
    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.1 until yield
    end
  rescue Timeout::Error
    flunk message
  end

  test "792px以下でフッターに5つのリンクが表示される" do
    set_viewport(390, 844)
    visit "/"

    # visible: true が既定。display:none なら 0 件になりここで落ちる。
    assert_selector "#sp-footer-links a", count: EXPECTED_LINKS.size

    within "#sp-footer-links" do
      EXPECTED_LINKS.each do |label, path|
        assert_link label, href: path
      end
    end

    # 縦2列であること
    columns = page.evaluate_script(<<~JS)
      getComputedStyle(document.querySelector('#sp-footer-links ul')).gridTemplateColumns
    JS
    assert_equal 2, columns.split.size,
      "リンクは縦2列で表示される想定 (grid-template-columns: #{columns})"
  end

  test "792px以下で各リンクが正しい遷移先へ飛ぶ" do
    EXPECTED_LINKS.each do |label, path|
      set_viewport(390, 844)
      visit "/"
      within("#sp-footer-links") { click_link label }
      assert_current_path path
    end
  end

  test "793px以上ではsp-footer-linksが表示されずPCのフッターが出る" do
    set_viewport(793, 900)
    visit "/"

    # PC で出るとリンクが二重になる
    assert_no_selector "#sp-footer-links a"
    assert_selector "#footer .footer-middle a", minimum: 1
  end

  # 下部の固定ボタン（.new_customer_banner / .price_banner）は position:fixed で
  # 画面下 60px を占める。#sp-footer-links の padding-bottom が足りないと
  # 最下行のリンクがこれに覆われてタップできなくなる。
  #
  # 320px は現行スマホで最も狭い部類。ボタン側の高さが px 固定なのに対し
  # #sp-footer-links の余白を vw で書くと狭い幅ほど詰まるため、
  # 最悪ケースになるこの幅で判定する。
  test "792px以下でリンクが下部の固定ボタンに覆われていない" do
    set_viewport(320, 568)
    visit "/"

    # 固定ボタンの表示は price_banner.js が scroll イベントで行う。ハンドラは
    # DOMContentLoaded で登録されるため、登録前に一度スクロールしただけだと
    # 二度と scroll が来ず、ボタンが出ないまま判定してしまう。
    # 上→下を繰り返して本物の scroll イベントを起こし、出るまで待つ。
    wait_until("固定ボタン(.floating)が表示されなかった") do
      page.execute_script(<<~JS)
        window.scrollTo({ top: 0, behavior: 'instant' });
        window.scrollTo({ top: document.documentElement.scrollHeight, behavior: 'instant' });
      JS
      page.has_selector?(".floating", visible: true, minimum: 1, wait: 0)
    end

    # スクロールが落ち着き、リンクが画面内に入るまで待つ。
    # 画面外だと elementFromPoint が null を返し、覆われていると誤判定する。
    wait_until("#sp-footer-links が画面内に収まらなかった") do
      page.evaluate_script(<<~JS)
        (() => {
          const r = document.querySelector('#sp-footer-links').getBoundingClientRect();
          return r.top >= 0 && r.bottom <= window.innerHeight;
        })()
      JS
    end

    # 判定は固定ボタンが実際に見えている前提で行う
    assert_selector ".floating", visible: true, minimum: 1

    # 判定は2つ。
    # 1. リンクの中心にある要素がリンク自身か（elementFromPoint）
    #    → 全面を覆われている場合を捕まえる。
    # 2. リンクの矩形が固定ボタンの矩形と1pxでも重なっていないか
    #    → 中心は生きているが下端だけ潜り込んでいる、を捕まえる。
    #      中心だけ見ると padding-bottom を 0 にしても通ってしまうため必要。
    covered = page.evaluate_script(<<~JS)
      (() => {
        const bars = [...document.querySelectorAll('.floating')]
          .filter(e => getComputedStyle(e).visibility === 'visible')
          .map(e => e.getBoundingClientRect());

        return [...document.querySelectorAll('#sp-footer-links a')].filter(a => {
          const r = a.getBoundingClientRect();

          const el = document.elementFromPoint(r.x + r.width / 2, r.y + r.height / 2);
          if (!(el && el.closest('#sp-footer-links'))) return true;

          return bars.some(b =>
            r.left < b.right && r.right > b.left && r.top < b.bottom && r.bottom > b.top
          );
        }).map(a => a.textContent.trim());
      })()
    JS

    assert_empty covered,
      "固定ボタンに覆われているリンクがある: #{covered.join(', ')}。" \
      "#sp-footer-links の padding-bottom を増やすこと"
  end
end

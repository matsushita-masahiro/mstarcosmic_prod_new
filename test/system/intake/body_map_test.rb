require "application_system_test_case"

# intake（患者が iPad で触る画面）の実ブラウザテスト。
#
# intake は QR の入口 → 同意書 → 問診票 → 提出 の多段フローで、
# 人体図や手書き欄は JS が無いと成立しない。ここはその足がかりとして、
# 「トークンで入って問診票に到達し、人体図が操作できる」ところまでを押さえる。
#
# 人体図のマーキングは 0.0〜1.0 の相対座標で保存され、viewBox 0 0 100 100 の
# SVG に cx = x * 100 で描き戻される（body_map_controller.js）。
# 図（_body_figure.html.erb）を描き直しても既存の座標と互換であることを、
# 実際にクリックして確かめる。
#
# 落ちたときは図の viewBox・data-body-map-target・SVG の表示サイズが
# 変わっていないかを先に疑うこと。座標系が変わると過去のマーキングがズレる。
#
# 注意: intake はサブドメイン制約付きのため app_host の指定が要る。
# test 環境の tld_length = 0 は config/environments/test.rb で設定済み。
class Intake::BodyMapTest < ApplicationSystemTestCase
  setup do
    @original_app_host = Capybara.app_host
    @original_include_port = Capybara.always_include_port
    Capybara.always_include_port = true
    Capybara.app_host = "http://intake.localhost"

    document = ConsentDocument.create!(
      version: "system-test", title: "同意書", body: "本文", published_at: Time.current
    )
    issuer  = User.create!(email: "issuer-bodymap@example.com", name: "発行者", password: "password")
    @patient = User.create!(email: "patient-bodymap@example.com", name: "患者", password: "password")

    # 同意書の署名フローはここでは対象外なので、同意済みの状態を先に作る
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

  test "入口トークンから問診票に到達し、人体図が表・裏とも描画される" do
    visit "/s/#{@intake_session.raw_token}"

    # 入口はトークンをセッションに移してから同意書へ送る（URL にトークンを残さない）
    assert_no_match(/#{@intake_session.raw_token}/, current_url)

    visit "/questionnaire"

    assert_selector '[data-body-map-target="front"]'
    assert_selector '[data-body-map-target="back"]'
  end

  test "人体図をタップするとマーカーが打て、すべて消すで消える" do
    visit "/s/#{@intake_session.raw_token}"
    visit "/questionnaire"

    # 左前腕を狙う。腕の輪郭は y=45 付近で x=26.5〜32。
    click_body_figure("front", 27, 45)

    marks = all("circle.body-mark")
    assert_equal 1, marks.size, "タップでマーカーが1つ打たれること"

    # タップ位置が viewBox 座標にそのまま変換されること。
    # ここがズレると、過去に保存したマーキングが別の部位に描き戻される。
    assert_in_delta 27.0, marks.first[:cx].to_f, 2.0, "タップした x が viewBox の x に一致すること"
    assert_in_delta 45.0, marks.first[:cy].to_f, 2.0, "タップした y が viewBox の y に一致すること"

    # 裏面にも独立して打てる（胴体の中央）
    click_body_figure("back", 50, 45)
    assert_equal 2, all("circle.body-mark").size

    assert_match(/2 か所/, find('[data-body-map-target="list"]').text)

    click_button "すべて消す"

    assert_equal 0, all("circle.body-mark").size, "すべて消すでマーカーが消えること"
    assert_match(/タップしてください/, find('[data-body-map-target="list"]').text)
  end

  test "マーカーをタップすると個別に削除できる" do
    visit "/s/#{@intake_session.raw_token}"
    visit "/questionnaire"

    click_body_figure("front", 27, 45)
    click_body_figure("front", 50, 45)
    assert_equal 2, all("circle.body-mark").size

    all("circle.body-mark").first.click

    assert_equal 1, all("circle.body-mark").size, "マーカー自身のタップで1件だけ消えること"
  end

  private

  # viewBox 座標（0〜100）を指定して人体図をクリックする。
  #
  # Capybara の click(x:, y:) は要素の中心からの px オフセットなので、
  # 実際の描画サイズを測ってから換算する。SVG の表示幅は CSS（max-width と
  # 親要素の幅）で決まるため、px を決め打ちにすると画面幅で壊れる。
  def click_body_figure(side, view_x, view_y)
    element = find(%([data-body-map-target="#{side}"]))
    size = page.evaluate_script(<<~JS)
      (() => {
        const r = document.querySelector('[data-body-map-target="#{side}"]').getBoundingClientRect();
        return { w: r.width, h: r.height };
      })()
    JS

    offset_x = (view_x / 100.0 * size["w"]) - (size["w"] / 2)
    offset_y = (view_y / 100.0 * size["h"]) - (size["h"] / 2)
    element.click(x: offset_x.round, y: offset_y.round)
  end
end

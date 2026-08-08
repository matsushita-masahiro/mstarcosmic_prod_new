require "application_system_test_case"

class PrivacyPageTest < ApplicationSystemTestCase
  test "未ログインでプライバシーポリシーを閲覧できる" do
    visit "/privacy"

    assert_selector "h1", text: "プライバシーポリシー"
    assert_text "11. お問い合わせ窓口"
    assert_text "制定日"
  end

  # 個人の携帯番号を公開しないため、窓口はフォームに寄せている。
  # 番号を書き戻す場合は公開してよい番号かを確認すること。
  test "お問い合わせ窓口に電話番号を載せず、フォームへ誘導している" do
    visit "/privacy"

    assert_no_text "080-4426-3718"

    within(:xpath, "//th[text()='お問い合わせフォーム']/parent::tr") do
      click_link "こちらから"
    end
    assert_current_path new_inquiry_path
  end

  test "フッターのリンクからプライバシーポリシーへ遷移できる" do
    visit "/"

    within("#footer") { click_link "プライバシーポリシー" }

    assert_selector "h1", text: "プライバシーポリシー"
    assert_current_path "/privacy"
  end
end

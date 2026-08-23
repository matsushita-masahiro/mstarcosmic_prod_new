# 管理メニューの表示条件と、リンク先の実ガードの対応。
#
# ── このファイルが守っているもの ──────────────────────
#
# 「メニューに出ているのに押すと弾かれる」
# 「メニューに出ていないのに到達できる」
# のどちらも事故なので、1つの表から両方を検証する。
#
# 実際に両方の事故を起こしている:
#   - payments#show をスタッフ限定にして購入完了画面を壊した（出ているのに弾かれる）
#   - SP オーバーレイが user_signed_in? だけで全項目を出していた（判定漏れ）
#
# メニューを増やすとき・権限を変えるときは、必ず MENU に1行足すこと。
# コントローラだけ直して表を放置すると、この対応が静かに崩れる。
#
# ── 表の読み方 ────────────────────────────────────
# sees:  そのロールのヘッダーにリンクが描画されるべきか
# reach: :ok      … 到達できる（200）
#        :blocked … 権限で弾かれる（リダイレクト）
#
# ── ガードが無い項目について ──────────────────────
# 料金表 / 予約カレンダー / 予約一覧 は権限判定を持たない。
# メニューの出し分けだけで見せ方を変えており、URL を直接叩けば到達できる。
# これは既知かつ意図的な状態（料金表は全員に見せる仕様、予約系は会員自身の
# 画面で my_reserved は非管理者なら自分の予約しか出さない）。
# guarded: false でその旨を明示し、「弾かれること」は要求しない。
require "test_helper"

class StaffMenuTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  MENU = [
    # ── 管理者・スタッフの両方に出す ──
    { label: "カルテ・施術記録", path: "/karte/users",
      sees: %i[admin staff], guarded: true,
      admin: :ok, staff: :ok, member: :blocked },
    { label: "スケジュール", path: "/admin/staffs",
      sees: %i[admin staff], guarded: true,
      admin: :ok, staff: :ok, member: :blocked },
    { label: "お客様一覧", path: "/users",
      sees: %i[admin staff], guarded: true,
      admin: :ok, staff: :ok, member: :blocked },
    { label: "回数券管理", path: "/payments",
      sees: %i[admin staff], guarded: true,
      admin: :ok, staff: :ok, member: :blocked },
    { label: "料金表", path: "/price_plan_admin",
      sees: %i[admin staff], guarded: false,
      admin: :ok, staff: :ok, member: :ok },

    # ── 管理者だけに出す ──
    { label: "同意書編集", path: "/karte/consent_documents",
      sees: %i[admin], guarded: true,
      admin: :ok, staff: :blocked, member: :blocked },
    { label: "お問合せ一覧", path: "/inquiries",
      sees: %i[admin], guarded: true,
      admin: :ok, staff: :blocked, member: :blocked },
    { label: "メタトロン購入問合せ", path: "/metatron_sale_inquiries",
      sees: %i[admin], guarded: true,
      admin: :ok, staff: :blocked, member: :blocked },
    { label: "出張登録", path: "/admin/machines/h/machine_schedules",
      sees: %i[admin], guarded: true,
      admin: :ok, staff: :blocked, member: :blocked },
    { label: "算命", path: "/sanmeis/menu",
      sees: %i[admin], guarded: true,
      admin: :ok, staff: :blocked, member: :blocked },
    { label: "ページ別文章管理", path: "/page_contents",
      sees: %i[admin], guarded: true,
      admin: :ok, staff: :blocked, member: :blocked },
    # 予約カレンダー / MY予約 は会員としての導線。管理者だけに出していたものを
    # _header 側と同じ条件（ログインしていれば出す）に揃え、1つに寄せた。
    { label: "予約カレンダー", path: "/reserves/machine_select",
      sees: %i[admin staff], guarded: false,
      admin: :ok, staff: :ok, member: :ok },
    { label: "MY予約", path: "/reserves/my_reserved",
      sees: %i[admin staff], guarded: false,
      admin: :ok, staff: :ok, member: :ok }
  ].freeze

  # main.html.erb はヘッダーを排他で出すため、管理者・スタッフには _header が
  # 描画されない。会員としての導線（プロフィール・回数券購入など）が
  # どこからも辿れなくなるので、_admin_header 側にも同じ項目を持たせている。
  #
  # markup が _header と重複している点は HANDOFF.md に記載。
  # 片方だけ直すと管理側と会員側で導線がずれるので、必ず両方を見ること。
  MEMBER_ITEMS = [
    { label: "プロフィール", path: "/users/edit" },
    { label: "回数券購入",   path: "/payments/pay_select" },
    { label: "予約カレンダー", path: "/reserves/machine_select" },
    { label: "MY予約",       path: "/reserves/my_reserved" }
  ].freeze

  setup do
    Rails.application.reload_routes_unless_loaded

    # payments.yml / page_contents.yml / machines.yml は Rails の雛形
    # （one: {} / two: {}）のままで、必須の値が nil の行が入る。
    # 各一覧のビューがその nil を無条件に触るため、残すと権限ではなく
    # ビューの nil で落ちる。
    Coupon.delete_all
    Payment.delete_all
    PageContent.delete_all
    Machine.delete_all

    # 出張登録は short_word で機械を引く。無いと nil を触って落ちる。
    Machine.create!(short_word: "h", name: "本店")

    @admin  = create_user(email: "menu-admin@example.com",  name: "管理者",     user_type: "1")
    @staff  = create_user(email: "menu-staff@example.com",  name: "施術スタッフ", user_type: "10")
    @member = create_user(email: "menu-member@example.com", name: "一般会員",   user_type: "2")
  end

  # ── 1. ヘッダーそのものの出し分けと見出しのラベル ──
  #
  # 見出しはロールで呼び替える（管理者→「管理者メニュー」/ スタッフ→
  # 「スタッフメニュー」）。ヘッダーが描画されたかどうかの判定にも使うので、
  # 「片方のラベルが出て、もう片方が出ない」を対で見る。

  ADMIN_LABEL = "管理者メニュー".freeze
  STAFF_LABEL = "スタッフメニュー".freeze

  test "管理者には見出しが管理者メニューで描画される" do
    sign_in @admin
    get root_path

    assert_response :success
    assert_includes response.body, ADMIN_LABEL,
                    "管理者に _admin_header が描画されていません"
    assert_not_includes response.body, STAFF_LABEL,
                        "管理者にスタッフ向けの見出しが出ています"
  end

  test "スタッフには見出しがスタッフメニューで描画される" do
    sign_in @staff
    get root_path

    assert_response :success
    assert_includes response.body, STAFF_LABEL,
                    "スタッフに _admin_header が描画されていません"
    assert_not_includes response.body, ADMIN_LABEL,
                        "スタッフに「管理者メニュー」の文字列が出ています"
  end

  test "見出しはPCドロップダウンに出る" do
    sign_in @staff
    get root_path
    assert_includes pc_header(response.body), STAFF_LABEL
    sign_out @staff

    sign_in @admin
    get root_path
    assert_includes pc_header(response.body), ADMIN_LABEL
  end

  # SP のスライドメニューは項目を平らに並べるだけで見出しを持たない。
  # PC だけの要素なので、どちらのラベルも出ないのが正しい。
  # ここに見出しを足すなら、この期待も一緒に更新すること。
  test "SPオーバーレイには見出しが無い" do
    %i[admin staff].each do |role|
      sign_in user_for(role)
      get root_path
      overlay = sp_overlay(response.body)

      assert_not_includes overlay, ADMIN_LABEL, "#{role} のSPに見出しが出ています"
      assert_not_includes overlay, STAFF_LABEL, "#{role} のSPに見出しが出ています"
      sign_out user_for(role)
    end
  end

  test "一般会員には管理側ヘッダーが描画されない" do
    sign_in @member
    get root_path

    assert_not_includes response.body, ADMIN_LABEL,
                        "一般会員に管理メニューが描画されています"
    assert_not_includes response.body, STAFF_LABEL
  end

  test "未ログインには管理側ヘッダーが描画されない" do
    get root_path

    assert_not_includes response.body, ADMIN_LABEL
    assert_not_includes response.body, STAFF_LABEL
  end

  # ── 2. メニューの表示（PC・SP の両方）────────────

  MENU.each do |item|
    test "PCメニュー: #{item[:label]} の表示が表のとおり" do
      %i[admin staff].each do |role|
        sign_in user_for(role)
        get root_path
        section = pc_header(response.body)

        if item[:sees].include?(role)
          assert_includes section, %(href="#{item[:path]}"),
                          "#{role} のPCメニューに #{item[:label]} が出ていません"
        else
          assert_not_includes section, %(href="#{item[:path]}"),
                              "#{role} のPCメニューに #{item[:label]} が出ています"
        end
        sign_out user_for(role)
      end
    end

    test "SPメニュー: #{item[:label]} の表示がPCと揃っている" do
      %i[admin staff].each do |role|
        sign_in user_for(role)
        get root_path
        section = sp_overlay(response.body)

        if item[:sees].include?(role)
          assert_includes section, %(href="#{item[:path]}"),
                          "#{role} のSPオーバーレイに #{item[:label]} が出ていません"
        else
          assert_not_includes section, %(href="#{item[:path]}"),
                              "#{role} のSPオーバーレイに #{item[:label]} が出ています"
        end
        sign_out user_for(role)
      end
    end
  end

  test "一般会員のヘッダーには管理メニューのリンクが1つも出ない" do
    sign_in @member
    get root_path

    MENU.reject { |i| i[:guarded] == false }.each do |item|
      assert_not_includes response.body, %(href="#{item[:path]}"),
                          "一般会員に #{item[:label]} が出ています"
    end
  end

  # ── 3. 実際の到達可否 ────────────────────────────

  MENU.each do |item|
    test "到達可否: #{item[:label]}" do
      { admin: @admin, staff: @staff, member: @member }.each do |role, user|
        sign_in user
        get item[:path]

        case item[role]
        when :ok
          assert_response :success,
                          "#{role} が #{item[:label]}（#{item[:path]}）に到達できません"
        when :blocked
          assert_response :redirect,
                          "#{role} が #{item[:label]}（#{item[:path]}）に到達できています"
        end
        sign_out user
      end
    end
  end

  test "未ログインでは管理メニューのどこにも到達できない" do
    MENU.select { |i| i[:guarded] }.each do |item|
      get item[:path]
      assert_response :redirect, "未ログインで #{item[:label]} に到達できています"
    end
  end

  # ── 4. 表示と実ガードの突き合わせ ────────────────
  #
  # 表そのものが矛盾していないかを見る。
  # 「出しているのに弾かれる」組み合わせを表に書いた時点で落とす。

  test "表示すると決めた項目は、そのロールが必ず到達できる" do
    MENU.each do |item|
      item[:sees].each do |role|
        assert_equal :ok, item[role],
                     "#{item[:label]} を #{role} に表示する設定なのに到達できない設定になっています"
      end
    end
  end

  test "ガードのある項目は、表示しないロールが必ず弾かれる" do
    MENU.select { |i| i[:guarded] }.each do |item|
      (%i[admin staff member] - item[:sees]).each do |role|
        assert_equal :blocked, item[role],
                     "#{item[:label]} を #{role} に表示しない設定なのに到達できる設定になっています"
      end
    end
  end

  # ── 4.5 会員としての導線 ─────────────────────────
  #
  # 管理者・スタッフも施術を受け、自分の登録情報を直す。
  # _header が描画されない以上、_admin_header に無いとどこからも辿れない。

  test "会員導線がスタッフのPC・SPに出る" do
    sign_in @staff
    get root_path

    MEMBER_ITEMS.each do |item|
      assert_includes pc_header(response.body), %(href="#{item[:path]}"),
                      "スタッフのPCメニューに #{item[:label]} が出ていません"
      assert_includes sp_overlay(response.body), %(href="#{item[:path]}"),
                      "スタッフのSPメニューに #{item[:label]} が出ていません"
    end
  end

  test "会員導線が管理者のPC・SPに出る" do
    sign_in @admin
    get root_path

    MEMBER_ITEMS.each do |item|
      assert_includes pc_header(response.body), %(href="#{item[:path]}"),
                      "管理者のPCメニューに #{item[:label]} が出ていません"
      assert_includes sp_overlay(response.body), %(href="#{item[:path]}"),
                      "管理者のSPメニューに #{item[:label]} が出ていません"
    end
  end

  test "必ずお読みください がスタッフに出る" do
    sign_in @staff
    get root_path

    # user_type ごとにページが違うので、パスは本人の区分で組み立てる。
    path = "/home/readmust/#{@staff.user_type}"
    assert_includes pc_header(response.body), %(href="#{path}")
    assert_includes sp_overlay(response.body), %(href="#{path}")
  end

  # 一般会員は _header のまま。今回の変更で何も変わっていないこと。
  test "一般会員の会員導線は従来どおり出る" do
    sign_in @member
    get root_path

    assert_response :success
    MEMBER_ITEMS.each do |item|
      assert_includes response.body, %(href="#{item[:path]}"),
                      "一般会員から #{item[:label]} が消えています"
    end
  end

  test "スタッフにお問合せボタンは出ない" do
    sign_in @staff
    get root_path

    assert_not_includes pc_header(response.body), %(href="/inquiries/new"),
                        "スタッフにお問合せボタンが出ています"
  end

  test "一般会員にはお問合せボタンが出る" do
    sign_in @member
    get root_path

    assert_includes response.body, %(href="/inquiries/new")
  end

  # ── 4.6 同じリンクが2つ並んでいないこと ──────────
  #
  # 会員導線を _admin_header に足したとき、管理者側に元からあった
  # 「予約カレンダー」「予約一覧」と重複した。1つに寄せてある。

  test "PCメニューに同じパスのリンクが2つ以上出ていない" do
    %i[admin staff].each do |role|
      sign_in user_for(role)
      get root_path

      assert_empty duplicated_hrefs(pc_header(response.body)),
                   "#{role} のPCメニューに同じリンクが重複しています"
      sign_out user_for(role)
    end
  end

  test "SPメニューに同じパスのリンクが2つ以上出ていない" do
    %i[admin staff].each do |role|
      sign_in user_for(role)
      get root_path

      assert_empty duplicated_hrefs(sp_overlay(response.body)),
                   "#{role} のSPメニューに同じリンクが重複しています"
      sign_out user_for(role)
    end
  end

  # ── 5. 一覧の中の押せないリンク ──────────────────
  #
  # お客様一覧はスタッフにも開いたが、氏名リンク（編集画面）と削除は
  # 管理者しか実行できない。一覧に出したままだと押した先で弾かれる。

  test "お客様一覧の削除リンクはスタッフに出ない" do
    sign_in @staff
    get users_path

    assert_response :success
    assert_no_match(/削除/, response.body, "スタッフに削除リンクが出ています")
  end

  test "お客様一覧の氏名リンクはスタッフに出ない" do
    sign_in @staff
    get users_path

    assert_not_includes response.body, %(href="/users/#{@member.id}/edit"),
                        "スタッフに編集画面へのリンクが出ています"
  end

  test "お客様一覧の削除リンクは管理者には出る" do
    sign_in @admin
    get users_path

    assert_match(/削除/, response.body, "管理者から削除リンクが消えています")
    assert_includes response.body, %(href="/users/#{@member.id}/edit")
  end

  private

  def user_for(role)
    { admin: @admin, staff: @staff, member: @member }.fetch(role)
  end

  # 同じ href が2回以上出ている箇所を返す。
  # ロゴとメニュー項目で "/" が重なる程度は許容したいので、
  # ルートだけは除いて見る。
  def duplicated_hrefs(section)
    section.scan(/href="([^"]*)"/).flatten
           .reject { |h| h.empty? || h == "/" }
           .tally.select { |_, count| count > 1 }.keys
  end

  # PC ヘッダー（<div id="new-header"> 〜 <div id="sp-new-header"> の手前）
  def pc_header(body)
    body[/<div id="new-header">.*?(?=<div id="sp-new-header">)/m].to_s
  end

  # SP のスライドメニュー
  def sp_overlay(body)
    body[/<div class="overlay">.*?<\/section>/m].to_s
  end

  # introducer まで埋めるのは registration_completed? を満たすため。
  # 欠けていると reserves 側の redirect_edit_user が先に効いて、
  # 権限ではなく登録未完了で弾かれ、何を見ているのか分からなくなる。
  def create_user(email:, name:, user_type:)
    User.create!(email: email, name: name, password: "password", user_type: user_type,
                 name_kana: "てすと", tel: "0312345678", introducer: "紹介者",
                 birthday: Date.new(1990, 1, 1), gender: "f")
  end
end

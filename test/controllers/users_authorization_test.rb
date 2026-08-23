# 会員情報の編集経路の権限（UsersController）。
#
# ── このファイルが守っているもの ──────────────────────
#
# 1. 他人のアカウントを触れないこと（所有者判定）
#    user_login はログイン済みかどうかしか見ていなかったため、URL の :id を
#    差し替えるだけで他人の編集画面に入り、メール・パスワードまで
#    書き換えられた。owner_or_admin_login が塞いでいる。
#
# 2. 自分自身を管理者に昇格できないこと（user_type の permit）
#    所有者判定だけでは「自分の編集画面から user_type: "1" を送る」経路が残る。
#    update_params が管理者のときだけ :user_type を permit することで塞ぐ。
#    Devise 経由の同じ穴は users_registrations_authorization_test の担当。
#
# 3. 管理者の既存フローが壊れていないこと
#    管理者は他人を編集でき、user_type も変更できる（users/edit の欄）。
#
# 4. backup_users が管理者限定であること
#    全 User を読んで UserBackup を作り直すのに、フィルタが1つも無かった。
#
# ── 注意 ──────────────────────────────────────────
# User は name_kana / tel / birthday / gender を on: :update で必須にしている。
# 更新のテストではこれらを必ず一緒に送ること（欠けると権限ではなく
# バリデーションで落ち、テストが通ったように見えて何も検証できない）。
require "test_helper"

class UsersAuthorizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Rails.application.reload_routes_unless_loaded

    @member = create_user(email: "member-authz@example.com", name: "会員本人", user_type: "2")
    @other  = create_user(email: "other-authz@example.com",  name: "別の会員", user_type: "2")
    @admin  = create_user(email: "admin-authz@example.com",  name: "管理者",   user_type: "1")
  end

  # ── 1. 所有者判定 ──────────────────────────────

  test "会員は他人の編集画面に入れない" do
    sign_in @member

    get edit_user_path(@other)

    assert_redirected_to new_user_session_path
    assert_equal "アクセス権限がありません", flash[:alert]
  end

  test "会員は他人を更新できない" do
    sign_in @member

    patch user_path(@other), params: { user: valid_attributes(name: "書き換えられた") }

    assert_redirected_to new_user_session_path
    assert_equal "別の会員", @other.reload.name
  end

  test "会員は自分の編集画面には入れる" do
    sign_in @member

    get edit_user_path(@member)

    assert_response :success
  end

  test "会員は他人の show に入れない" do
    sign_in @member

    get user_path(@other)

    assert_redirected_to new_user_session_path
    assert_equal "アクセス権限がありません", flash[:alert]
  end

  test "会員は自分の show には入れる（edit へ飛ぶ）" do
    sign_in @member

    get user_path(@member)

    assert_redirected_to edit_user_path(@member)
  end

  test "未ログインでは編集画面に入れない" do
    get edit_user_path(@member)

    assert_redirected_to new_user_session_path
  end

  # ── 2. 自分自身の昇格 ──────────────────────────

  test "会員が自分に user_type 1 を送っても昇格しない" do
    sign_in @member

    patch user_path(@member), params: { user: valid_attributes(user_type: "1") }

    assert_equal "2", @member.reload.user_type, "会員が自分を管理者に昇格できています"
  end

  test "会員の自分のプロフィール更新は user_type 以外なら成功する" do
    sign_in @member

    patch user_path(@member), params: {
      user: valid_attributes(name: "変更後の名前", tel: "0399998888")
    }

    @member.reload
    assert_equal "変更後の名前", @member.name
    assert_equal "0399998888", @member.tel
    assert_equal "2", @member.user_type
  end

  # ── 3. 管理者の既存フロー ──────────────────────

  test "管理者は他人の編集画面に入れる" do
    sign_in @admin

    get edit_user_path(@other)

    assert_response :success
  end

  test "管理者は会員の user_type を変更できる" do
    sign_in @admin

    patch user_path(@other), params: { user: valid_attributes(name: "別の会員", user_type: "10") }

    assert_equal "10", @other.reload.user_type, "管理者が user_type を変更できなくなっています"
  end

  # ── 4. backup_users ────────────────────────────

  test "未ログインでは backup_users に到達できない" do
    UserBackup.delete_all

    get backup_users_path

    assert_response :redirect
    assert_equal 0, UserBackup.count, "未ログインでバックアップが走っています"
  end

  test "会員は backup_users に到達できない" do
    UserBackup.delete_all
    sign_in @member

    get backup_users_path

    assert_response :redirect
    assert_equal 0, UserBackup.count, "会員がバックアップを実行できています"
  end

  test "管理者は backup_users を実行できる" do
    UserBackup.delete_all
    sign_in @admin

    get backup_users_path

    assert_redirected_to users_path
    assert_operator UserBackup.count, :>, 0
  end

  private

  def create_user(email:, name:, user_type:)
    User.create!(email: email, name: name, password: "password", user_type: user_type,
                 name_kana: "てすと", tel: "0312345678",
                 birthday: Date.new(1990, 1, 1), gender: "f")
  end

  # on: :update の必須項目を全て埋めた更新パラメータ。
  # 上書きしたい項目だけキーワードで渡す。
  def valid_attributes(**overrides)
    { name: "テスト", name_kana: "てすと", tel: "0312345678",
      birthday: "1990-01-01", gender: "f" }.merge(overrides)
  end
end

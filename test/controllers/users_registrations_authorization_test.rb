# Devise の登録情報編集（PUT /users → Users::RegistrationsController#update）の権限。
#
# ── このファイルが守っているもの ──────────────────────
#
# 1. 自分自身を管理者に昇格できないこと
#    account_update の対象は current_user 自身なので、ID の差し替えすら要らず、
#    自分の登録情報編集から user_type: "1" を送るだけで昇格できた。
#    UsersController#update_params と同じ穴の別経路。
#    片方だけ直すと経路が残るため、両方をテストで押さえる
#    （UsersController 側は users_authorization_test の担当）。
#
# 2. 会員本人の通常の編集が壊れていないこと
#    塞ぎ方を間違えると permit ごと落ちて、名前もメールも変えられなくなる。
#
# 3. 管理者は従来どおり user_type を変更できること
require "test_helper"

class UsersRegistrationsAuthorizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Rails.application.reload_routes_unless_loaded

    @member = create_user(email: "member-devise@example.com", name: "会員本人", user_type: "2")
    @admin  = create_user(email: "admin-devise@example.com",  name: "管理者",   user_type: "1")
  end

  # ── 1. 自分自身の昇格 ──────────────────────────

  test "会員が Devise 経由で user_type 1 を送っても昇格しない" do
    sign_in @member

    put user_registration_path, params: { user: account_update_attributes(user_type: "1") }

    assert_equal "2", @member.reload.user_type,
                 "Devise 経由で会員が自分を管理者に昇格できています"
  end

  # ── 2. 会員本人の通常の編集 ────────────────────

  test "会員は Devise 経由で name を変更できる" do
    sign_in @member

    put user_registration_path, params: { user: account_update_attributes(name: "変更後の名前") }

    @member.reload
    assert_equal "変更後の名前", @member.name
    assert_equal "2", @member.user_type
  end

  test "会員は Devise 経由で email を変更できる" do
    sign_in @member

    put user_registration_path,
        params: { user: account_update_attributes(email: "member-devise-changed@example.com") }

    @member.reload
    assert_equal "member-devise-changed@example.com", @member.email
    assert_equal "2", @member.user_type
  end

  test "現在のパスワードが違えば更新されない" do
    sign_in @member

    put user_registration_path, params: {
      user: account_update_attributes(name: "変わらない").merge(current_password: "wrong-password")
    }

    assert_equal "会員本人", @member.reload.name
  end

  # ── 3. 管理者の既存フロー ──────────────────────

  test "管理者は Devise 経由で user_type を変更できる" do
    sign_in @admin

    put user_registration_path, params: { user: account_update_attributes(user_type: "10") }

    assert_equal "10", @admin.reload.user_type,
                 "管理者が Devise 経由で user_type を変更できなくなっています"
  end

  # ── 4. ENV['USER_EMAIL'] による昇格が無いこと ──
  #
  # かつて registrations_controller#update には「ログイン中のメールが
  # ENV['USER_EMAIL'] と一致したら user_type を "1" にする」行があった。
  # @user = current_user に代入したインスタンスへ書いているだけで、Devise の
  # update は to_adapter.get! で resource を読み直すため保存経路が無く、
  # 元から昇格していなかった（削除前後の実測で確認済み）。
  #
  # 動いていないうえに「特定のメールなら無条件で管理者」は今回塞いだ穴と
  # 同種のため削除した。復活させないための番人としてこのテストを残す。
  test "ENV USER_EMAIL と一致しても昇格しない" do
    sign_in @member

    with_env("USER_EMAIL", @member.email) do
      put user_registration_path, params: { user: account_update_attributes(name: "自動昇格の確認") }
    end

    @member.reload
    assert_equal "自動昇格の確認", @member.name, "更新自体は成功している必要がある"
    assert_equal "2", @member.user_type,
                 "ENV['USER_EMAIL'] による昇格が復活しています"
  end

  test "ENV USER_EMAIL と一致しても user_type 1 を送れば弾かれる" do
    sign_in @member

    with_env("USER_EMAIL", @member.email) do
      put user_registration_path, params: { user: account_update_attributes(user_type: "1") }
    end

    assert_equal "2", @member.reload.user_type
  end

  private

  def create_user(email:, name:, user_type:)
    User.create!(email: email, name: name, password: "password", user_type: user_type,
                 name_kana: "てすと", tel: "0312345678",
                 birthday: Date.new(1990, 1, 1), gender: "f")
  end

  # on: :update の必須項目と current_password を全て埋めた更新パラメータ。
  def account_update_attributes(**overrides)
    { current_password: "password", name: "テスト", name_kana: "てすと",
      tel: "0312345678", birthday: "1990-01-01", gender: "f" }.merge(overrides)
  end

  def with_env(key, value)
    original = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = original
  end
end

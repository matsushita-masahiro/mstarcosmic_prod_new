require "test_helper"

# 会員の削除（DELETE /users/:id）の権限。
#
# ── なぜこのテストがあるか ────────────────────────
#
# before_action が index と show/edit/update にしか掛かっておらず、
# destroy はどのフィルタにも入っていなかった。ApplicationController に
# 共通フィルタも無いため、未ログインのリクエストがそのまま実行されていた。
# CSRF トークンはサイトを開けば誰でも取れるので、防波堤になっていない。
# staging で「未ログインの DELETE /users/999999」がアクションまで到達し、
# 500 になることを確認している（302 で止まっていなかった）。
#
# 患者は氏名・生年月日・問診票を持つ。削除は取り返しがつかないので、
# 「消せてしまう」より「権限が無ければ何も起きない」を先に守る。
#
# ── 何を守るか ───────────────────────────────
#
# 「302 が返ること」だけでは足りない。リダイレクトしていても削除が
# 走っていれば意味がないので、User.count が変わらないことまで見る。
class UsersDestroyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Rails.application.reload_routes_unless_loaded

    @admin   = User.create!(email: "admin-destroy@example.com", name: "管理者",
                            password: "password", user_type: "1")
    @staff   = User.create!(email: "staff-destroy@example.com", name: "施術スタッフ",
                            password: "password", user_type: "10")
    @patient = User.create!(email: "patient-destroy@example.com", name: "患者 太郎",
                            password: "password")
  end

  test "未ログインでは削除できない" do
    assert_no_difference "User.count" do
      delete user_path(@patient)
    end

    assert_response :redirect
    assert User.exists?(@patient.id), "未ログインのリクエストで患者が消えています"
  end

  # 施術スタッフ（user_type "10"）はカルテを見られるが、会員の削除は管理者だけ。
  # authenticate_staff_user? で守ると "10" が通ってしまう。
  test "権限のないログインユーザーでは削除できない" do
    sign_in @staff

    assert_no_difference "User.count" do
      delete user_path(@patient)
    end

    assert_response :redirect
    assert User.exists?(@patient.id), "権限の無いユーザーが患者を消せています"
  end

  test "一般ユーザーでも削除できない" do
    sign_in @patient
    other = User.create!(email: "other-destroy@example.com", name: "別の患者",
                         password: "password")

    assert_no_difference "User.count" do
      delete user_path(other)
    end

    assert User.exists?(other.id), "他人のアカウントを消せています"
  end

  # 既存の挙動。管理者は従来どおり削除できる。
  test "管理者は削除できる" do
    sign_in @admin

    assert_difference "User.count", -1 do
      delete user_path(@patient)
    end

    assert_redirected_to users_path
    assert_not User.exists?(@patient.id)
    assert_equal "患者 太郎様を削除しました", flash[:notice]
  end

  # ── 削除できる / できないの伝え方 ──────────────────
  #
  # 判定そのものは test/models/user_deletion_test.rb が見ている。
  # ここで見るのは「スタッフの画面に理由が出るか」。
  # 以前は外部キー違反が素の 500 になり、押しても何が起きたのか分からなかった。

  test "カルテ記録のある会員は削除できず、理由が画面に出る" do
    sign_in @admin
    @patient.medical_questionnaires.create!(form_version: MedicalQuestionnaireForm::VERSION)

    assert_no_difference "User.count" do
      delete user_path(@patient)
    end

    assert_redirected_to users_path
    assert_equal "患者 太郎様: この会員には問診票 1件の記録があるため削除できません",
                 flash[:alert]
    assert User.exists?(@patient.id)
  end

  # 誤登録の掃除。カルテを一度開いていても消せること（閲覧ログは一緒に消える）。
  test "カルテを閲覧しただけの会員は削除できる" do
    sign_in @admin
    KarteAccessLog.record!(actor: @admin, patient: @patient, action: "show")

    assert_difference "User.count", -1 do
      delete user_path(@patient)
    end

    assert_equal "患者 太郎様を削除しました", flash[:notice]
    assert_empty KarteAccessLog.where(patient_id: @patient.id)
  end

  # スタッフは物理削除しない運用なので、外部キーで止まるのが正しい。
  # ただし 500 で終わらせず、止まったことを伝える。
  test "他の記録から参照されている会員は 500 にせず理由を出す" do
    sign_in @admin
    IntakeSession.issue!(patient: @patient, issuer: @staff)

    assert_no_difference "User.count" do
      delete user_path(@staff)
    end

    assert_redirected_to users_path
    assert_equal "施術スタッフ様は他の記録から参照されているため削除できませんでした",
                 flash[:alert]
  end

  # @user が nil のとき、未定義の name を参照して落ちていた
  # （その手前の logger.debug も nil を触っていた）。
  # 消せなかったことを画面に伝えて一覧へ戻す。
  test "存在しない会員を削除しようとしても落ちない" do
    sign_in @admin

    assert_no_difference "User.count" do
      delete user_path(id: 999_999)
    end

    assert_redirected_to users_path
    assert flash[:alert].present?, "削除できなかったことが伝わっていません"
  end
end

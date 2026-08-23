# 回数券（PaymentsController）の権限。
#
# ── このファイルが守っているもの ──────────────────────
#
# show / edit / update / destroy には権限判定が1つも無く、掛かっていたのは
# access_controll_payment だけだった。あれは名前に反して「そのレコードが
# 存在するか」しか見ておらず、所有者も user_type も見ていない。
# そのため、ログインしていれば誰でも :id を差し替えて
#   - 他人の回数券と個人情報を閲覧でき（show / edit）
#   - 他人の残回数を1枚消費でき（update）
#   - 使用済みを未使用に戻して自分の残回数を無制限に増やせた（destroy）
# payment_destroy に至ってはコメントに「管理者のみ実行可能」とありながら
# 誰でも他人の支払レコードごと削除できた。
#
# ここは「会員（user_type "2"）が弾かれること」と
# 「窓口業務として施術スタッフ（"10"）が通ること」を対で守る。
#
# access_controll_payment は存在確認として今も有効なので残してある。
# 権限判定を先に走らせているため、存在しない :id でも
# 権限の無い相手には権限エラーが返る（存在の有無を漏らさない）。
require "test_helper"

class PaymentsAuthorizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Rails.application.reload_routes_unless_loaded

    @member = create_user(email: "member-pay@example.com", name: "会員本人", user_type: "2")
    @staff  = create_user(email: "staff-pay@example.com",  name: "施術スタッフ", user_type: "10")
    @admin  = create_user(email: "admin-pay@example.com",  name: "管理者", user_type: "1")

    # payments.yml / coupons.yml は Rails の雛形（one: {} / two: {}）のままで、
    # user_id が nil の支払いが2件入る。一覧のビューが
    # User.find_by(id: payment.user_id).name を無条件に呼ぶため、
    # 残したままだと権限ではなくビューの nil で落ちる。
    Coupon.delete_all
    Payment.delete_all

    # 他人（@member ではない人）の支払い。会員がこれを触れないことを見る。
    @payment = Payment.create!(user: @admin, price: 10_000)
    @used    = Coupon.create!(payment: @payment, status: "used", order_number: 1)
    @unused  = Coupon.create!(payment: @payment, status: "new",  order_number: 2)
  end

  # ── 会員は弾かれる ─────────────────────────────

  test "会員は他人の回数券の編集画面に入れない" do
    sign_in @member

    get edit_payment_path(@payment)

    assert_response :redirect
    assert_equal "権限がありません", flash[:alert]
  end

  test "会員は他人の回数券の詳細を見られない" do
    sign_in @member

    get payment_path(@payment)

    assert_response :redirect
    assert_equal "権限がありません", flash[:alert]
  end

  test "会員は他人の回数券を消費できない" do
    sign_in @member

    patch payment_path(@payment), params: { payment: { remarks: "不正" } }

    assert_response :redirect
    assert_equal "new", @unused.reload.status, "会員が他人の回数券を消費できています"
  end

  test "会員は回数券の使用を取り消せない" do
    sign_in @member

    delete payment_path(@payment)

    assert_response :redirect
    assert_equal "used", @used.reload.status,
                 "会員が使用済みの回数券を未使用に戻せています（残回数の水増し）"
  end

  test "会員は支払レコードを削除できない" do
    sign_in @member

    delete "/payment_destroy/#{@payment.id}"

    assert_response :redirect
    assert Payment.exists?(@payment.id), "会員が他人の支払レコードを削除できています"
  end

  test "会員は回数券一覧に入れない" do
    sign_in @member

    get payments_path

    assert_response :redirect
  end

  # ── 施術スタッフは窓口業務として通る ──────────

  test "スタッフは回数券の編集画面に入れる" do
    sign_in @staff

    get edit_payment_path(@payment)

    assert_response :success
  end

  test "スタッフは回数券を1枚消費できる" do
    sign_in @staff

    patch payment_path(@payment), params: { payment: { remarks: "施術1回" } }

    assert_equal "used", @unused.reload.status
  end

  test "スタッフは回数券の使用を取り消せる" do
    sign_in @staff

    delete payment_path(@payment)

    assert_equal "new", @used.reload.status
  end

  test "スタッフは支払レコードごとの削除はできない" do
    sign_in @staff

    delete "/payment_destroy/#{@payment.id}"

    assert_response :redirect
    assert Payment.exists?(@payment.id), "スタッフが支払レコードを削除できています"
  end

  test "スタッフは回数券一覧に入れない" do
    sign_in @staff

    get payments_path

    assert_response :redirect
  end

  # ── 管理者は従来どおり全て通る ─────────────────

  test "管理者は回数券一覧に入れる" do
    sign_in @admin

    get payments_path

    assert_response :success
  end

  test "管理者は支払レコードを削除できる" do
    sign_in @admin

    delete "/payment_destroy/#{@payment.id}"

    assert_not Payment.exists?(@payment.id), "管理者が支払レコードを削除できなくなっています"
  end

  # ── 会員自身の購入フロー ────────────────────────
  #
  # /payments/:id/new の :id は支払 ID ではなく「発行する回数券の枚数」で、
  # そのまま session に入り complete_cash_payment が :id 回だけ Coupon を作る。
  # 検証が無かったため /payments/9999/new を開いて現金払いへ進むだけで
  # 9999 枚を発行できた。許可枚数は ALLOWED_COUPON_COUNTS が正。

  test "会員は購入フローの入口に入れる" do
    sign_in @member

    get "/payments/pay_select"

    assert_response :success
  end

  test "購入ボタンは定数から作られる" do
    sign_in @member

    get "/payments/pay_select"

    PaymentsController::ALLOWED_COUPON_COUNTS.each do |count|
      assert_match %r{/payments/#{count}/new}, response.body,
                   "#{count}回のボタンがビューに出ていません"
    end
  end

  test "許可された枚数なら購入フローに進める" do
    sign_in @member

    get "/payments/#{PaymentsController::ALLOWED_COUPON_COUNTS.first}/new"

    assert_response :success
  end

  test "許可外の枚数は new で弾かれる" do
    sign_in @member

    get "/payments/9999/new"

    assert_redirected_to payments_pay_select_path
    assert_equal "選択できない回数券です", flash[:alert]
  end

  test "許可外の枚数では回数券が発行されない" do
    sign_in @member
    before = Coupon.count

    get "/payments/9999/new"
    get payments_complete_cash_payment_path

    assert_equal before, Coupon.count, "許可外の枚数で回数券が発行されています"
  end

  test "0 や負数も弾かれる" do
    sign_in @member

    ["0", "-5"].each do |bad|
      get "/payments/#{bad}/new"
      assert_redirected_to payments_pay_select_path, "#{bad} が通っています"
    end
  end

  # 数値化すると許可枚数に化ける表記を弾く。to_i で比べると "05" や "5abc" が
  # 5 として通ってしまうため、判定は文字列で行っている。
  #
  # なお "/payments/5.0/new" や "/payments/10.5/new" は Rails が "." 以降を
  # format として切り落とすため params[:id] が "5" / "10" になる。
  # 許可枚数そのものに落ちるので抜け道ではない（枚数は増えない）。
  test "数値化すれば通る表記も弾かれる" do
    sign_in @member

    ["05", "5abc"].each do |bad|
      get "/payments/#{bad}/new"
      assert_redirected_to payments_pay_select_path, "#{bad} が通っています"
    end
  end

  test "正規の枚数なら現金払いでその枚数だけ発行される" do
    sign_in @member
    count = PaymentsController::ALLOWED_COUPON_COUNTS.first

    get "/payments/#{count}/new"
    get payments_complete_cash_payment_path

    payment = Payment.where(user_id: @member.id).order(:id).last
    assert_not_nil payment, "支払レコードが作られていません"
    assert_equal count, payment.coupons.count
    assert_equal count, payment.coupons.where(status: "new").count
  end

  # session を直接書き換えられた場合の最後の砦。
  # new を通さずに complete_cash_payment だけを叩く経路を模している。
  test "session を経ずに現金払いだけ叩いても発行されない" do
    sign_in @member
    before = Coupon.count

    get payments_complete_cash_payment_path

    assert_redirected_to payments_pay_select_path
    assert_equal before, Coupon.count
  end

  private

  def create_user(email:, name:, user_type:)
    User.create!(email: email, name: name, password: "password", user_type: user_type,
                 name_kana: "てすと", tel: "0312345678",
                 birthday: Date.new(1990, 1, 1), gender: "f")
  end
end

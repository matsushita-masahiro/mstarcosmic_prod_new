require "test_helper"

# DELETE /api/v1/reserves/:id は medirosa の多段POSTロールバック専用。
#
# 画面側の ReservesController#destroy は root_reserve_id で引いているが、
# ロールバックが必要になるのは root_reserve_id をまだ設定できていない瞬間。
# あのキーで引くと一番消したいレコードが消せないので、id 単体で消すこと。
class ApiReserveDestroyTest < ActionDispatch::IntegrationTest
  API_KEY = "test-api-key-for-destroy".freeze

  setup do
    @original_api_key = ENV["API_KEY"]
    ENV["API_KEY"] = API_KEY

    Reserve.delete_all
    Reservation.delete_all
    @staff = Staff.find_or_create_by!(id: 3) do |s|
      s.name = "はるか"
      s.name_kanji = "花香"
    end
    @user = User.find_or_create_by!(id: 9001) do |u|
      u.email = "destroy-test@example.test"
      u.name = "検証ユーザー"
      u.password = "password123456"
    end
  end

  teardown do
    ENV["API_KEY"] = @original_api_key
  end

  def auth_headers(key = API_KEY)
    { "Authorization" => "Bearer #{key}" }
  end

  def create_reservation(reserve, start_time)
    Reservation.create!(
      user_id: @user.id, staff_id: @staff.id, service: "stem",
      date: reserve.reserved_date, start_time: start_time,
      end_time: "11:00", duration: 60, status: 0
    )
  end

  def build_reserve(space:, root: :self, date: Date.new(2026, 9, 20))
    r = Reserve.create!(
      user_id: @user.id, staff_id: @staff.id, machine: "stem",
      reserved_date: date, reserved_space: space
    )
    r.update!(root_reserve_id: r.id) if root == :self
    r.update!(root_reserve_id: root) if root.is_a?(Integer)
    r
  end

  # --- 認証 ---

  test "Authorizationヘッダ無しは401" do
    r = build_reserve(space: 10.0)
    delete "/api/v1/reserves/#{r.id}"
    assert_response :unauthorized
    assert Reserve.exists?(r.id), "未認証なのに削除されている"
  end

  test "誤ったAPIキーは401" do
    r = build_reserve(space: 10.0)
    delete "/api/v1/reserves/#{r.id}", headers: auth_headers("wrong-key")
    assert_response :unauthorized
    assert Reserve.exists?(r.id)
  end

  # --- 正常系 ---

  test "存在するidを削除すると204で消える" do
    r = build_reserve(space: 10.0)

    delete "/api/v1/reserves/#{r.id}", headers: auth_headers

    assert_response :no_content
    refute Reserve.exists?(r.id)
  end

  test "存在しないidは404" do
    delete "/api/v1/reserves/999999999", headers: auth_headers
    assert_response :not_found
  end

  # --- 本命: root_reserve_id が nil のレコード ---

  test "root_reserve_idがnilのレコードを削除できる" do
    # 多段POSTの1枠目をPOSTした直後、PATCHで root_reserve_id を
    # 自分自身に設定する前の状態。ロールバックはまさにこの瞬間に走る。
    r = build_reserve(space: 10.0, root: nil)
    assert_nil r.root_reserve_id

    delete "/api/v1/reserves/#{r.id}", headers: auth_headers

    assert_response :no_content
    refute Reserve.exists?(r.id), "root_reserve_id が nil だと消えない実装になっている"
  end

  # --- 巻き添え防止 ---

  test "同じグループの他のレコードを巻き添えで消さない" do
    parent = build_reserve(space: 10.0)
    child = build_reserve(space: 10.5, root: parent.id)

    delete "/api/v1/reserves/#{parent.id}", headers: auth_headers

    assert_response :no_content
    refute Reserve.exists?(parent.id)
    assert Reserve.exists?(child.id), "指定していない子レコードまで消えている"
  end

  test "無関係なレコードを消さない" do
    target = build_reserve(space: 10.0, root: nil)
    other = build_reserve(space: 14.0, root: nil)

    delete "/api/v1/reserves/#{target.id}", headers: auth_headers

    assert_response :no_content
    assert_equal [other.id], Reserve.pluck(:id)
  end

  test "1回のリクエストで消えるのはちょうど1件" do
    build_reserve(space: 10.0, root: nil)
    build_reserve(space: 10.5, root: nil)
    target = build_reserve(space: 11.0, root: nil)

    assert_difference -> { Reserve.count }, -1 do
      delete "/api/v1/reserves/#{target.id}", headers: auth_headers
    end
  end

  # --- after_destroy による Reservation 側の掃除 ---
  #
  # Reserve#remove_from_reservations は after_destroy で
  #   group = Reserve.where(root_reserve_id: root_reserve_id || id)
  #   min_space = group.minimum(:reserved_space)  → start_time を組み立てる
  # としているが、この時点で自分は既に消えている。
  # そのため min_space が「残っているレコードの最小値」になり、
  # 削除したのが先頭スロットだと start_time がずれて Reservation に一致しない。
  #
  # 以下は期待を書いたものではなく、実際の挙動を固定したもの。
  # C-2 の削除順序はこの結果に依存する。

  test "先頭スロットから消すとReservationは掃除されない" do
    # 10:00 を消すと、残った 10:30 から start_time が "10:30" と算出され、
    # "10:00" の Reservation には一致しない。
    parent = build_reserve(space: 10.0)
    build_reserve(space: 10.5, root: parent.id)
    reservation = create_reservation(parent, "10:00")

    delete "/api/v1/reserves/#{parent.id}", headers: auth_headers
    assert_response :no_content

    assert Reservation.exists?(reservation.id),
           "挙動が変わった。C-2 の削除順序を見直すこと"
  end

  test "後ろのスロットから消すとReservationが掃除される" do
    # 10:30 を消すと、残った 10:00 から start_time が "10:00" と算出され、
    # Reservation に一致して destroy_all が効く。
    # **ロールバックは後ろのスロットから消すこと。**
    parent = build_reserve(space: 10.0)
    child = build_reserve(space: 10.5, root: parent.id)
    reservation = create_reservation(parent, "10:00")

    delete "/api/v1/reserves/#{child.id}", headers: auth_headers
    assert_response :no_content

    refute Reservation.exists?(reservation.id),
           "後ろから消しても Reservation が残る。C-2 の前提が崩れる"
  end

  test "兄弟のいない1件を消すとReservationは残る" do
    # group が空になり early return するため Reservation に到達しない。
    r = build_reserve(space: 10.0)
    reservation = create_reservation(r, "10:00")

    delete "/api/v1/reserves/#{r.id}", headers: auth_headers
    assert_response :no_content

    assert Reservation.exists?(reservation.id),
           "挙動が変わった。C-2 の前提を見直すこと"
  end

  test "root_reserve_idがnilのレコードにはReservationがそもそも紐づかない" do
    # PATCH 前の状態。sync_group_to_reservations は root_reserve_id == id の
    # ときにしか走らないので、この時点で Reservation は作られていない。
    r = build_reserve(space: 10.0, root: nil)

    assert_equal 0, Reservation.count

    delete "/api/v1/reserves/#{r.id}", headers: auth_headers
    assert_response :no_content
    assert_equal 0, Reservation.count
  end
end

require "test_helper"

# machines エンドポイント追加が既存APIに影響していないことの回帰確認。
# これらは medirosa が消費している契約であり、レスポンス形・キー集合・
# ステータスコードが変わると medirosa が壊れる。
class ApiExistingEndpointsRegressionTest < ActionDispatch::IntegrationTest
  API_KEY = "test-api-key-for-regression".freeze

  # 各エンドポイントが返すべきキー集合 = そのテーブルの全カラム。
  # ハードコードではなくモデルから引くことで、
  # 「カラムを足したのにAPIに出ていない」も「勝手に絞られた」も検出できる。
  ENDPOINTS = {
    "/api/v1/reserves"                 => Reserve,
    "/api/v1/schedules"                => Schedule,
    "/api/v1/staffs"                   => Staff,
    "/api/v1/staff_machine_relations"  => StaffMachineRelation
  }.freeze

  setup do
    @original_api_key = ENV["API_KEY"]
    ENV["API_KEY"] = API_KEY
  end

  teardown do
    ENV["API_KEY"] = @original_api_key
  end

  def auth_headers(key = API_KEY)
    { "Authorization" => "Bearer #{key}" }
  end

  test "既存エンドポイントは認証なしで401のまま" do
    ENDPOINTS.each_key do |path|
      get path
      assert_response :unauthorized, "#{path} が401を返さない"
    end
  end

  test "既存エンドポイントは認証ありで200のJSON配列を返す" do
    ENDPOINTS.each_key do |path|
      get path, headers: auth_headers
      assert_response :success, "#{path} が200を返さない"
      assert_kind_of Array, JSON.parse(response.body), "#{path} が配列を返さない"
    end
  end

  test "既存エンドポイントのキー集合が変化していない" do
    ENDPOINTS.each do |path, model|
      get path, headers: auth_headers
      rows = JSON.parse(response.body)
      next if rows.empty?

      assert_equal model.column_names.sort, rows.first.keys.sort,
                   "#{path} のレスポンスのキー集合が #{model.name} のカラムと一致しない"
    end
  end

  test "schedules と reserves の date 絞り込みが従来どおり効く" do
    get "/api/v1/schedules", params: { date: "2026-09-01" }, headers: auth_headers
    assert_response :success
    JSON.parse(response.body).each do |row|
      assert_equal "2026-09-01", row["schedule_date"]
    end

    get "/api/v1/reserves", params: { date: "2026-09-01" }, headers: auth_headers
    assert_response :success
    JSON.parse(response.body).each do |row|
      assert_equal "2026-09-01", row["reserved_date"]
    end
  end
end

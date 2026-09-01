require "test_helper"

# GET /api/v1/machines は medirosa が機器台数(number_of_machine)を読むための
# エンドポイント。medirosa の空き判定と mstarcosmic 旧予約画面
# (reserves_controller.rb:487) が同じ machines テーブルを根拠にするための土台。
class ApiMachinesTest < ActionDispatch::IntegrationTest
  API_KEY = "test-api-key-for-machines".freeze

  setup do
    @original_api_key = ENV["API_KEY"]
    ENV["API_KEY"] = API_KEY

    Machine.delete_all
    @stem = Machine.create!(id: 120, short_word: "stem", name: "幹細胞", number_of_machine: 2)
    Machine.create!(id: 121, short_word: "h", name: "ホリスティック", number_of_machine: 2)
  end

  teardown do
    ENV["API_KEY"] = @original_api_key
  end

  def auth_headers(key = API_KEY)
    { "Authorization" => "Bearer #{key}" }
  end

  # --- 認証 ---

  test "Authorizationヘッダ無しは401" do
    get "/api/v1/machines"
    assert_response :unauthorized
  end

  test "誤ったAPIキーは401" do
    get "/api/v1/machines", headers: auth_headers("wrong-key")
    assert_response :unauthorized
  end

  test "認証されていない場合は機器情報を一切返さない" do
    get "/api/v1/machines"
    assert_response :unauthorized
    refute_includes response.body, "stem"
  end

  # --- 正常系 ---

  test "認証ありでmachinesが返る" do
    get "/api/v1/machines", headers: auth_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_kind_of Array, body
    assert_equal 2, body.size
  end

  test "stem(id=120)が含まれnumber_of_machineが取得できる" do
    get "/api/v1/machines", headers: auth_headers

    body = JSON.parse(response.body)
    stem = body.find { |m| m["short_word"] == "stem" }

    refute_nil stem, "short_word=stem の機器がレスポンスに含まれていない"
    assert_equal 120, stem["id"]
    assert_equal 2, stem["number_of_machine"]
  end

  # medirosa が参照するキー名が揃っていること。
  # ここが崩れると medirosa 側は nil を掴んで台数0扱いになり、
  # 全枠が ✘ になるか、逆に判定が素通りする。
  test "medirosaが必要とする項目が揃っている" do
    get "/api/v1/machines", headers: auth_headers

    stem = JSON.parse(response.body).find { |m| m["short_word"] == "stem" }
    %w[id short_word name number_of_machine].each do |key|
      assert stem.key?(key), "レスポンスに #{key} が無い"
    end
  end
end

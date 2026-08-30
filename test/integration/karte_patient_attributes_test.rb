require "test_helper"

# カルテ詳細（/karte/users/:id）の属性行。
#
#   ほりなかまささ ／ 1987/06/19（39歳） ／ 男性 ／ A型 ／ 07085915737
#
# ── 血液型がここに出る理由 ────────────────────────────
#
# 施術判断に使う。生年月日・性別と並ぶ身体属性なので性別の直後に置き、
# 連絡先である電話番号はその後ろに残す。
#
# ── 未確定の2状態を畳まないこと ────────────────────────
#
#   "unknown" … 訊いたが患者が知らなかった → もう一度訊いても得られない
#   nil       … まだ訊いていない          → 次回の問診票で埋まる
#
# 同じ表示にするとスタッフの取るべき行動が読めなくなる。表示が壊れても
# 例外は出ず静かに間違うので、落ちたときはテストの方を直さないこと。
class KartePatientAttributesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    # routes は遅延ロードのため、先に読ませないと Devise.mappings が空で sign_in が落ちる
    Rails.application.reload_routes_unless_loaded

    @staff = User.create!(email: "staff-attrs@example.com", name: "スタッフ",
                          password: "password", user_type: "1")
    sign_in @staff
  end

  # 属性行そのもの。氏名（h2）とは別の <p> にある。
  def attributes_line(user)
    get karte_user_path(user)
    assert_response :success

    css_select("p").map(&:text).find { |t| t.include?(user.name_kana) }
  end

  def patient(label, **attrs)
    User.create!(email: "patient-attrs-#{label}@example.com",
                 name: "堀中 まささ", name_kana: "ほりなかまささ",
                 password: "password", user_type: "0", **attrs)
  end

  # ── 血液型の3状態 ────────────────────────────
  test "登録済みの血液型は日本語ラベルで出る" do
    { "a" => "A型", "b" => "B型", "o" => "O型", "ab" => "AB型" }.each do |value, expected|
      line = attributes_line(patient("t#{value}", gender: "m", blood_type: value))

      assert_includes line, expected, "blood_type=#{value.inspect} が出ていません"
    end
  end

  test "訊いて不明だった患者は不明と出る" do
    line = attributes_line(patient("unknown", gender: "m", blood_type: "unknown"))

    assert_includes line, "不明"
    assert_not_includes line, "血液型未登録",
                        "訊いた患者に、まだ訊いていない表示が出ています"
  end

  test "まだ訊いていない患者は血液型未登録と出る" do
    line = attributes_line(patient("nil", gender: "m", blood_type: nil))

    assert_includes line, "血液型未登録",
                     "空欄だと「訊いたが不明」と見分けが付きません"
  end

  # 生値を画面に出さない。訊き直せば埋まる側に倒す。
  test "定義に無い値は生値を出さず未登録に倒す" do
    line = attributes_line(patient("undefined", gender: "m", blood_type: "a+"))

    assert_not_includes line, "a+", "生値がカルテに出ています"
    assert_includes line, "血液型未登録"
  end

  # ── 並び順 ──────────────────────────────
  #
  # 性別の直後・電話番号の前。身体属性がまとまっていること。
  # 位置がずれても画面は普通に描けてしまうので、順序そのものを見る。
  # 出ていない項目を index で比べると nil で落ちて、順序の問題なのか
  # 表示そのものが消えたのか読めない。先に有無を確かめてから順序を見る。
  def assert_order(line, *fragments)
    fragments.each do |fragment|
      assert_includes line, fragment, "#{fragment} が属性行に出ていません"
    end

    positions = fragments.map { |fragment| line.index(fragment) }
    assert_equal positions.sort, positions,
                 "属性行の並びが #{fragments.join(' → ')} になっていません: #{line.squish}"
  end

  test "血液型は性別の直後・電話番号の前に出る" do
    line = attributes_line(patient("order", gender: "m", blood_type: "a",
                                   birthday: Date.new(1987, 6, 19),
                                   tel: "07085915737"))

    assert_order(line, "ほりなかまささ", "1987/06/19", "男性", "A型", "07085915737")
  end

  # 未登録でも位置は変わらないこと。項目ごと消す作りにしていない。
  test "未登録でも血液型は性別と電話番号の間に出る" do
    line = attributes_line(patient("order-nil", gender: "f", blood_type: nil,
                                   tel: "07085915737"))

    assert_order(line, "女性", "血液型未登録", "07085915737")
  end

  # ── 既存の表示を壊していないこと ──────────────────────
  test "氏名カナ・生年月日・年齢・性別・電話番号は今までどおり出る" do
    travel_to Date.new(2026, 8, 31) do
      line = attributes_line(patient("existing", gender: "m", blood_type: "a",
                                     birthday: Date.new(1987, 6, 19),
                                     tel: "07085915737"))

      assert_includes line, "ほりなかまささ"
      assert_includes line, "1987/06/19"
      assert_includes line, "39歳"
      assert_includes line, "男性"
      assert_includes line, "07085915737"
    end
  end

  # 生年月日・電話番号は元から条件付きで、無ければ項目ごと消える。
  # 血液型を足したことでこの出し分けが壊れていないこと。
  test "生年月日と電話番号が無い患者でも壊れない" do
    line = attributes_line(patient("sparse", gender: "f", blood_type: "o",
                                   birthday: nil, tel: nil))

    assert_includes line, "ほりなかまささ"
    assert_includes line, "女性"
    assert_includes line, "O型"
    assert_not_includes line, "歳"
  end

  # 性別も血液型も未登録の患者。文言が2つ並ぶが、どちらの項目かは読める。
  # （性別側は元から "未登録"、血液型側は "血液型未登録"）
  test "性別も血液型も未登録ならどちらの項目か分かる" do
    line = attributes_line(patient("both-nil", gender: nil, blood_type: nil))

    assert_includes line, "未登録"
    assert_includes line, "血液型未登録"
  end
end

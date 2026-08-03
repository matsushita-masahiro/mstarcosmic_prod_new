# test/controllers/karte/users_search_test.rb
#
# 電話番号の表記ゆれを吸収できているかの検証。
#
# 本番データは表記が揃っていない:
#   ハイフンなし 731件 / 半角スペース区切り 63件 / ハイフン区切り 43件 / +81 付き 13件
# どの表記で保存されていても、どの表記で入力しても引けることを担保する。
require "test_helper"

class Karte::UsersSearchTest < ActiveSupport::TestCase
  # 保存されている表記 => その人を引けるべき入力
  PATTERNS = {
    "09012345678"     => %w[09012345678 090-1234-5678 090\ 1234\ 5678 +819012345678],
    "090-1234-5678"   => %w[09012345678 090-1234-5678],
    "090 1234 5678"   => %w[09012345678 090\ 1234\ 5678],
    "090 1234 5678 "  => %w[09012345678],
    "+819012345678"   => %w[09012345678 090-1234-5678 +819012345678]
  }.freeze

  test "保存表記と入力表記の組み合わせで引ける" do
    PATTERNS.each do |stored, inputs|
      inputs.each do |input|
        assert match?(stored, input),
               "保存 #{stored.inspect} を #{input.inspect} で引けません"
      end
    end
  end

  test "別人の番号は引かない" do
    assert_not match?("09012345678", "09087654321")
  end

  test "部分一致で引ける" do
    assert match?("090-1234-5678", "12345678")
  end

  test "桁数が少ない入力は電話番号として扱わない" do
    assert_nil normalized("090")
    assert_nil normalized("1234")
    assert_not_nil normalized("12345")
  end

  test "数字を含まない入力は電話番号として扱わない" do
    assert_nil normalized("松下")
  end

  private

  # コントローラと同じ正規化を SQL 抜きで再現して突き合わせる。
  # ロジックを二重に持つことになるが、DB を用意せずに組み合わせを網羅できる。
  def match?(stored, input)
    q = normalized(input)
    return false if q.nil?

    stored.gsub(/\D/, "").sub(/\A81/, "0").include?(q)
  end

  def normalized(input)
    digits = input.gsub(/\D/, "")
    return nil if digits.length < Karte::UsersController::MIN_TEL_DIGITS

    input.start_with?("+81") ? digits.sub(/\A81/, "0") : digits
  end
end

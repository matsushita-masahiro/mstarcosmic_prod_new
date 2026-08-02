require "test_helper"

class Karte::UsersPagingTest < ActiveSupport::TestCase
  test "総ページ数の計算が境界で正しい" do
    per = Karte::UsersController::PER_PAGE
    assert_equal 1, (per / per.to_f).ceil
    assert_equal 2, ((per + 1) / per.to_f).ceil
    assert_equal 0, (0 / per.to_f).ceil
  end

  test "PER_PAGE が 50 である" do
    assert_equal 50, Karte::UsersController::PER_PAGE
  end
end

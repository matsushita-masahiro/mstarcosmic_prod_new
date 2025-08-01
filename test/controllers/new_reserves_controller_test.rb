require "test_helper"

class NewReservesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get new_reserves_index_url
    assert_response :success
  end

  test "should get show" do
    get new_reserves_show_url
    assert_response :success
  end

  test "should get confirm" do
    get new_reserves_confirm_url
    assert_response :success
  end

  test "should get new" do
    get new_reserves_new_url
    assert_response :success
  end
end

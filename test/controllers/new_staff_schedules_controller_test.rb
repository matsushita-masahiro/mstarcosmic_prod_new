require "test_helper"

class NewStaffSchedulesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get new_staff_schedules_index_url
    assert_response :success
  end
end

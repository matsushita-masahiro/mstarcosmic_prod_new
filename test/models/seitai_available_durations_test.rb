require "test_helper"

# その枠から実際に取れる施術時間の一覧。
#
# 選択肢を固定で並べないための計算。エステは 60/90/120/150 を直書きしており、
# 選んだ長さが空いているかを確かめていない。整体は30分刻みで細かく埋まるため、
# 同じ作りだと「○ を押して120分を選んだら30分しか空いていなかった」が起きる。
class SeitaiAvailableDurationsTest < ActiveSupport::TestCase
  setup do
    @service = Service.find_or_create_by!(name: "seitai") do |s|
      s.display_name = "整体"
      s.max_concurrent = 1
    end
    @service.update!(min_duration: 30, max_duration: 120, active: true)

    @staff = Staff.create!(name: "整体スタッフ", name_kanji: "整体 太郎",
                           active_flag: true, dismiss_flag: false, new_customer_flag: true)
    StaffService.create!(staff_id: @staff.id, service: "seitai")
    @date = Date.current + 7
    StaffSchedule.create!(staff_id: @staff.id, date: @date,
                          start_time: t("10:00"), end_time: t("22:00"))
    @patient = User.create!(email: "dur-p@example.com", name: "患者", password: "password")
  end

  # ── 1. 完全に空いている ────────────────────────
  test "空いた枠では30分刻みで max_duration まで出る" do
    assert_equal [ 30, 60, 90, 120 ], durations("10:30")
  end

  # ── 2. 30分後が埋まっている ──────────────────────
  test "30分後が埋まっていれば30分だけ" do
    reserve("11:00", "11:30")

    assert_equal [ 30 ], durations("10:30")
  end

  # ── 3. 60分後が埋まっている ──────────────────────
  test "60分後が埋まっていれば30分と60分" do
    reserve("11:30", "12:00")

    assert_equal [ 30, 60 ], durations("10:30")
  end

  # ── 4-5. 営業終了（22:00）────────────────────────
  test "21時30分開始は30分だけ" do
    assert_equal [ 30 ], durations("21:30")
  end

  test "21時開始は30分と60分" do
    assert_equal [ 30, 60 ], durations("21:00")
  end

  # ── 6. 飛び地を拾わない ───────────────────────
  #
  # 11:00 が埋まり 11:30 が空いていても、10:30 から90分は取れない。
  # 連続していない空きを足し合わせないこと。
  test "途中が埋まっていればその先の空きは含めない" do
    reserve("11:00", "11:30")

    assert_equal [ 30 ], durations("10:30"),
                 "飛び地（11:30の空き）を拾って [30, 90] になっています"
  end

  # max_duration が上限であること。120を超える長さを出さない。
  test "max_duration を超える長さは出ない" do
    assert_equal 120, durations("10:00").max
  end

  # max_duration は2-1 が初めて読む値。変えたら選択肢も変わること。
  test "max_duration を60にすると選択肢も60までになる" do
    @service.update!(max_duration: 60)

    assert_equal [ 30, 60 ], durations("10:30")
  end

  private

  def t(hhmm) = Time.zone.parse("2000-01-01 #{hhmm}")

  def durations(slot_time)
    AvailabilityService.available_durations("seitai", @date, slot_time)
  end

  def reserve(from, to)
    Reservation.create!(user_id: @patient.id, staff_id: @staff.id, service: "seitai",
                        date: @date, start_time: t(from), end_time: t(to),
                        duration: ((t(to) - t(from)) / 60).to_i, status: 0)
  end
end

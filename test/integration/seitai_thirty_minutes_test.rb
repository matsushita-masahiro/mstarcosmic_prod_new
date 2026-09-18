require "test_helper"

# 整体は1予約 = 30分枠1つ。
#
# frames は「何枠作るか」を決める値で、ReservesController#create が
# frames/30 回ループして reserved_space を +0.5 ずつ進める。
# 60 を送ると2枠（例: 11.0 と 11.5）になる。
#
# 施術時間は services.min_duration とビューの hidden_field で二重管理に
# なっている。片方だけ変えると予約枠と空き判定が食い違うため、
# 両方をここで押さえる。
class SeitaiThirtyMinutesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email: "st-admin@example.com", name: "管理者",
                          password: "password", user_type: "1")
    # registration_completed? が欠けている項目を数え、1つでもあると
    # redirect_edit_user（before_action）が create より先に飛ばす。
    # 紹介者まで埋めておかないと予約そのものが走らない。
    @member = User.create!(email: "st-member@example.com", name: "会員",
                           password: "password", user_type: "2",
                           name_kana: "かいいん", tel: "09000000000",
                           gender: "f", birthday: Date.new(1990, 1, 1),
                           introducer: "紹介者")
    @staff = Staff.create!(name: "整体スタッフ", name_kanji: "整体 太郎",
                           active_flag: true, dismiss_flag: false,
                           new_customer_flag: true)
    StaffMachineRelation.create!(staff_id: @staff.id, machine: "seitai")
    @date = Date.current + 7

    # 予約確定時に管理者宛メールを送る。宛先が引けないと create が
    # 例外で落ちるので、ENV['USER_EMAIL'] に管理者を差しておく。
    ENV["USER_EMAIL"] = @admin.email

    # available_space が Machine.find_by(short_word:).number_of_machine と
    # Schedule（出勤）を見るので、両方を用意する。
    [ %w[seitai 整体], %w[e エステ], %w[h holistic] ].each do |short_word, name|
      Machine.find_or_create_by!(short_word: short_word) do |m|
        m.name = name
        m.number_of_machine = 2
      end
    end
    # 11:00〜12:30 を出勤にする（90分の予約まで通るように）
    [ 11.0, 11.5, 12.0, 12.5 ].each do |space|
      Schedule.create!(staff_id: @staff.id, user_id: @staff.user_id,
                       schedule_date: @date, schedule_space: space)
    end
  end

  # ── 1. 整体は1行だけ ─────────────────────────
  test "整体の予約で reserves が1行だけ作られる" do
    sign_in @member

    assert_difference "Reserve.count", 1 do
      post reserves_path, params: reserve_params(machine: "seitai", frames: "30")
    end

    spaces = Reserve.where(machine: "seitai", reserved_date: @date).pluck(:reserved_space)
    assert_equal [ 11.0 ], spaces.map(&:to_f),
                 "整体が1枠になっていません（2枠なら 11.0 と 11.5 が入ります）"
  end

  # ── 整体の複数枠 ────────────────────────────
  test "整体60分で reserves が2行つくられる" do
    sign_in @member

    assert_difference "Reserve.count", 2 do
      post reserves_path, params: reserve_params(machine: "seitai", frames: "60")
    end

    assert_equal [ 11.0, 11.5 ], seitai_spaces
  end

  test "整体120分で reserves が4行つくられる" do
    sign_in @member

    assert_difference "Reserve.count", 4 do
      post reserves_path, params: reserve_params(machine: "seitai", frames: "120")
    end

    assert_equal [ 11.0, 11.5, 12.0, 12.5 ], seitai_spaces
  end

  # ── フォームに出る選択肢 ─────────────────────
  #
  # 計算（AvailabilityService.available_durations）は別テストで見ている。
  # ここは「計算結果がそのまま画面に出るか」だけを見る。
  test "空いた枠では30/60/90/120のラジオが出る" do
    prepare_service_staff
    sign_in @member

    get new_reserve_path, params: modal_params(space: "10.5"), xhr: true

    assert_response :success
    assert_match(/value=\\"30\\"/, response.body)
    assert_match(/value=\\"120\\"/, response.body)
  end

  # 選択肢が1つならラジオにしない。押させる意味がない。
  test "30分しか取れない枠ではラジオを出さず30分と表示する" do
    prepare_service_staff
    sign_in @member

    # 21:30 開始は営業終了22:00 まで30分しか取れない
    get new_reserve_path, params: modal_params(space: "21.5"), xhr: true

    assert_response :success
    assert_no_match(/radio_button|type=\\"radio\\"/, response.body,
                    "選択肢が1つなのにラジオが出ています")
    assert_match(/hidden.*frames/, response.body)
  end

  # ── 送信時検証（整体のみ）────────────────────────
  #
  # 既存の available_flag はループ内で毎回上書きされ、最後の枠の可否しか
  # 見ていない。先頭が埋まっていても素通りし、二重予約が作れる。
  # 整体は別経路で all? に畳んでいるので、ここで弾かれること。
  test "先頭の枠が埋まっていれば整体は1件も保存されない" do
    occupy(11.0)
    sign_in @member

    assert_no_difference "Reserve.count" do
      post reserves_path, params: reserve_params(machine: "seitai", frames: "60")
    end

    assert_equal "選択された時間はすでに予約が入っているため予約できませんでした",
                 flash[:alert]
  end

  test "途中の枠が埋まっていれば整体は1件も保存されない" do
    occupy(11.5)
    sign_in @member

    assert_no_difference "Reserve.count" do
      post reserves_path, params: reserve_params(machine: "seitai", frames: "60")
    end
  end

  # transaction で囲んでいること。途中で保存に失敗したら1件も残さない。
  # 2枠目の保存を失敗させ、1枠目が残らないことを見る。
  test "途中で保存に失敗したら整体の行は残らない" do
    sign_in @member
    # 2枠目（11.5）の保存だけ失敗させる。回数で数えると
    # root_reserve_id の更新も save を通るためズレる。
    original = Reserve.instance_method(:save)
    Reserve.define_method(:save) do |*args|
      return false if reserved_space.to_f == 11.5 && new_record?

      original.bind(self).call(*args)
    end

    begin
      assert_no_difference "Reserve.count" do
        post reserves_path, params: reserve_params(machine: "seitai", frames: "60")
      end
    ensure
      Reserve.define_method(:save, original)
    end
  end

  # ── エステは従来どおり（案Xの意図）────────────────
  #
  # エステの二重予約は今も作れる。見つけたが今回は直さないという判断を
  # ここで固定する。運用影響（今まで通っていた予約が弾かれる）を避けるため。
  # 本番の直近180日では重なりは holistic のみ42件で、すべて定員内。
  # 将来エステも塞ぐときは、このテストを意図的に反転させること。
  test "エステは先頭の枠が埋まっていても従来どおり保存される" do
    occupy(11.0, machine: "e")
    sign_in @member

    assert_difference "Reserve.count", 2 do
      post reserves_path, params: reserve_params(machine: "e", frames: "60")
    end
  end

  # ── 2. 他機器は従来どおり（デグレ検知）──────────────
  test "エステ60分は従来どおり2行つくられる" do
    sign_in @member

    assert_difference "Reserve.count", 2 do
      post reserves_path, params: reserve_params(machine: "e", frames: "60")
    end

    assert_equal [ 11.0, 11.5 ],
                 Reserve.where(machine: "e", reserved_date: @date).order(:reserved_space).pluck(:reserved_space).map(&:to_f)
  end

  test "エステ90分は従来どおり3行つくられる" do
    sign_in @member

    assert_difference "Reserve.count", 3 do
      post reserves_path, params: reserve_params(machine: "e", frames: "90")
    end

    assert_equal [ 11.0, 11.5, 12.0 ],
                 Reserve.where(machine: "e", reserved_date: @date).order(:reserved_space).pluck(:reserved_space).map(&:to_f)
  end

  # ── 3. 事前チェックの duration ───────────────────
  #
  # ここを 60 のまま残すと、整体を30分にしてもモーダルで弾かれ、
  # カレンダーの ✘ が移動するだけになる。
  test "整体の事前チェックは services.min_duration に従う" do
    service("seitai").update!(min_duration: 30)

    assert_equal 30, AvailabilityService.reservation_duration_minutes("seitai")
  end

  # 全サービスを min_duration 由来にすると鍼灸（min_duration=90）の
  # 予約可能枠が不当に狭まる。整体のみスコープしていることを固定する。
  test "整体以外の事前チェックは60分のまま" do
    service("shinkyu").update!(min_duration: 90)
    service("esute").update!(min_duration: 60, max_duration: 150)
    service("holistic").update!(min_duration: 60)

    assert_equal 60, AvailabilityService.reservation_duration_minutes("holistic")
    assert_equal 60, AvailabilityService.reservation_duration_minutes("esute")
    assert_equal 60, AvailabilityService.reservation_duration_minutes("shinkyu"),
                 "鍼灸まで min_duration 由来にすると予約可能枠が狭まります"
    assert_equal 60, AvailabilityService.reservation_duration_minutes("stem")
  end

  # services.min_duration を更新する前は整体も60を返すこと。
  # コード先行デプロイの中間状態が従来どおりであることを担保する。
  test "min_duration が60のうちは整体も60を返す" do
    service("seitai").update!(min_duration: 60)

    assert_equal 60, AvailabilityService.reservation_duration_minutes("seitai")
  end

  # ── 4. 非会員経路 ───────────────────────────
  #
  # このフォームは機器で分岐しておらず、?machine=seitai で来ると
  # frames=60（2枠）が送られ、サービス名も「ホリスティック」と誤表示されていた。
  test "非会員経路の整体でも reserves が1行だけ作られる" do
    assert_difference "Reserve.count", 1 do
      post reserves_path, params: new_customer_params(machine: "seitai",
                                                      frames: not_user_frames_for("seitai"))
    end

    assert_equal [ 11.0 ],
                 Reserve.where(machine: "seitai", reserved_date: @date).pluck(:reserved_space).map(&:to_f)
  end

  test "非会員経路のホリスティックは従来どおり2行つくられる" do
    assert_difference "Reserve.count", 2 do
      post reserves_path, params: new_customer_params(machine: "h",
                                                      frames: not_user_frames_for("h"))
    end
  end

  private

  # 非会員フォームは機器で分岐した hidden_field を送る。
  # 値を二重に書かないよう、テンプレートから読み出す。
  def not_user_frames_for(machine)
    src = Rails.root.join("app/views/reserves/_form_machine_staff_not_user.html.erb").read
    m = src[/hidden_field :frames, value: \(@machine == 'seitai' \? "(\d+)" : "(\d+)"\)/]
    raise "frames の書き方が変わりました" if m.nil?

    machine == "seitai" ? Regexp.last_match(1) : Regexp.last_match(2)
  end

  # モーダル（reserves#new）を開くための前提。
  # AvailabilityService は services / staff_services / staff_schedules を見る。
  def prepare_service_staff
    svc = service("seitai")
    svc.update!(min_duration: 30, max_duration: 120, max_concurrent: 1, active: true)
    StaffService.find_or_create_by!(staff_id: @staff.id, service: "seitai")

    # 出勤は 10:00〜22:00 に上書きする。setup の旧 Schedule が
    # StaffSchedule（11:00〜13:00）を同期で作っており、
    # find_or_create_by! だとそれを拾ってブロックが走らない。
    sched = StaffSchedule.find_or_initialize_by(staff_id: @staff.id, date: @date)
    sched.update!(start_time: Time.zone.parse("2000-01-01 10:00"),
                  end_time: Time.zone.parse("2000-01-01 22:00"))
  end

  def modal_params(space:)
    { date: @date.to_s, frame: space, start_date: @date.to_s,
      staff_id: @staff.id, machine: "seitai" }
  end

  def seitai_spaces
    Reserve.where(machine: "seitai", reserved_date: @date)
           .order(:reserved_space).pluck(:reserved_space).map(&:to_f)
  end

  # 先客がその枠を押さえている状態を作る。
  def occupy(space, machine: "seitai")
    other = User.create!(email: "occ-#{machine}-#{space}@example.com", name: "先客",
                         password: "password", user_type: "2")
    r = Reserve.create!(user_id: other.id, staff_id: @staff.id, reserved_date: @date,
                        reserved_space: space, machine: machine)
    r.update!(root_reserve_id: r.id)
    r
  end

  def service(name)
    Service.find_or_create_by!(name: name) do |s|
      s.display_name = name
      s.min_duration = 60
      s.max_duration = 60
    end
  end

  # 会員フォームは user_id を hidden で送る（_form_machine_staff.html.erb:106）。
  # 省くと belongs_to :user で保存に失敗し、枠数を見る前に落ちる。
  def reserve_params(machine:, frames:)
    { reserve: { reserved_date: @date.to_s, reserved_space: "11", staff_id: @staff.id,
                 user_id: @member.id, machine: machine, frames: frames, remarks: "",
                 start_date: @date.to_s } }
  end

  # 非会員フォームは user_id を送らず、コントローラが User を作って差す。
  def new_customer_params(machine:, frames:)
    reserve_params(machine: machine, frames: frames).tap do |p|
      p[:reserve].delete(:user_id)
      p[:reserve].merge!(name: "新規 太郎", name_kana: "しんき たろう",
                         email: "newcust-#{machine}@example.com",
                         tel: "09011112222", gender: "m")
    end
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password" } }
  end
end

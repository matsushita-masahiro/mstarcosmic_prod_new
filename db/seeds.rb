# 既存データをクリア
NewSchedule.destroy_all
BusinessTrip.destroy_all
NewReserve.destroy_all
NewStaff.destroy_all
NewMachine.destroy_all

# スタッフの初期データ
staff_masako = NewStaff.create!(id: 1,name: "まさこ", staff_type: :admin, active: true)
staff_haruka = NewStaff.create!(id: 2,name: "はるか", staff_type: :staff_x, active: true)
staff_yuki = NewStaff.create!(id: 3,name: "ゆうき", staff_type: :staff_x, active: true)

# マシンの初期データ
machine = NewMachine.create!(id: 1, name: "holistic", total_count: 2)

# 明日から30日間のスケジュールデータを作成
start_date = Date.tomorrow
(0..29).each do |day_offset|
  date = start_date + day_offset.days
  
  # 曜日を取得（0=日曜日, 1=月曜日, ..., 6=土曜日）
  wday = date.wday
  is_weekday = wday >= 1 && wday <= 5  # 月曜日から金曜日
  is_weekend = wday == 0 || wday == 6  # 土曜日と日曜日
  
  # 全日営業（休業日なし）
  # スケジュールを作成
    # 各スタッフの出勤スケジュール（10:00-22:00の時間枠）
    (0..24).each do |time_slot|
      # 8/14の特別な出勤パターン（goodステータス用）
      if date == Date.new(2025, 8, 14)
        # 8/14は特別にgoodステータスを作るため、特定の時間帯で1名のみ出勤
        if [0, 1, 2, 3].include?(time_slot)  # 10:00-12:00 - ゆうきのみ
          NewSchedule.create!(new_staff: staff_yuki, date: date, time_slot: time_slot, working: true)
        elsif [4, 5, 6, 7].include?(time_slot)  # 12:00-14:00 - まさこのみ
          NewSchedule.create!(new_staff: staff_masako, date: date, time_slot: time_slot, working: true)
        elsif [8, 9, 10, 11, 12, 13, 14, 15].include?(time_slot)  # 14:00-18:00 - はるかのみ
          NewSchedule.create!(new_staff: staff_haruka, date: date, time_slot: time_slot, working: true)
        else
          # 他の時間帯は通常通り複数名出勤
          NewSchedule.create!(new_staff: staff_masako, date: date, time_slot: time_slot, working: true)
          if time_slot >= 8
            NewSchedule.create!(new_staff: staff_haruka, date: date, time_slot: time_slot, working: true)
          end
          if time_slot < 12
            NewSchedule.create!(new_staff: staff_yuki, date: date, time_slot: time_slot, working: true)
          end
        end
      else
        # 通常の出勤パターン
        # まさこ（管理者）: 平日は全時間、土日は午前のみ
        if is_weekday || (is_weekend && time_slot < 8)
          NewSchedule.create!(
            new_staff: staff_masako,
            date: date,
            time_slot: time_slot,
            working: true
          )
        end
        
        # はるか: 平日午後、土日全時間
        if (is_weekday && time_slot >= 8) || is_weekend
          NewSchedule.create!(
            new_staff: staff_haruka,
            date: date,
            time_slot: time_slot,
            working: true
          )
        end
        
        # ゆうき: 平日午前、土日全時間
        if (is_weekday && time_slot < 12) || is_weekend
          NewSchedule.create!(
            new_staff: staff_yuki,
            date: date,
            time_slot: time_slot,
            working: true
          )
        end
      end
    end
end

# サンプル出張データ（マシンが1台出張中）
BusinessTrip.create!([
  { new_machine: machine, date: start_date + 2.days, time_slot: 10 },
  { new_machine: machine, date: start_date + 2.days, time_slot: 11 },
  { new_machine: machine, date: start_date + 4.days, time_slot: 14 },
  { new_machine: machine, date: start_date + 4.days, time_slot: 15 },
  { new_machine: machine, date: start_date + 10.days, time_slot: 8 },
  { new_machine: machine, date: start_date + 10.days, time_slot: 9 },
  

])

# サンプル予約データ（20個：60分17個、30分3個）
sample_reserves = []

# 顧客データ
customers = [
  { name: "田中太郎", gender: :customer_male, tel: "090-1234-5678" },
  { name: "佐藤花子", gender: :customer_female, tel: "080-9876-5432" },
  { name: "山田次郎", gender: :customer_male, tel: "070-1111-2222" },
  { name: "鈴木美咲", gender: :customer_female, tel: "090-3333-4444" },
  { name: "高橋健一", gender: :customer_male, tel: "080-5555-6666" },
  { name: "伊藤麻衣", gender: :customer_female, tel: "070-7777-8888" },
  { name: "渡辺雄介", gender: :customer_male, tel: "090-9999-0000" },
  { name: "中村由美", gender: :customer_female, tel: "080-1111-3333" },
  { name: "小林大輔", gender: :customer_male, tel: "070-2222-4444" },
  { name: "加藤愛子", gender: :customer_female, tel: "090-5555-7777" },
  { name: "吉田和也", gender: :customer_male, tel: "080-8888-1111" },
  { name: "松本真理", gender: :customer_female, tel: "070-3333-5555" },
  { name: "井上拓也", gender: :customer_male, tel: "090-6666-9999" },
  { name: "森田彩香", gender: :customer_female, tel: "080-4444-7777" },
  { name: "橋本慎一", gender: :customer_male, tel: "070-9999-2222" },
  { name: "清水優子", gender: :customer_female, tel: "090-7777-4444" },
  { name: "藤田光男", gender: :customer_male, tel: "080-2222-6666" },
  { name: "岡田恵子", gender: :customer_female, tel: "070-5555-8888" },
  { name: "石川正樹", gender: :customer_male, tel: "090-8888-3333" },
  { name: "村上千春", gender: :customer_female, tel: "080-6666-1111" }
]

notes_list = [
  "初回利用です", "肩こりが気になります", "腰痛改善希望", "リラックス目的",
  "定期利用", "ストレス解消", "疲労回復", "体調管理", "健康維持",
  "デトックス", "美容目的", "睡眠改善", "集中力向上", "免疫力アップ",
  "血行促進", "むくみ解消", "姿勢改善", "運動不足解消", "メンテナンス", ""
]

# 20個の予約データを作成（60分17個、30分3個）
durations = [2] * 17 + [1] * 3  # 60分17個、30分3個
durations.shuffle!

(0..19).each do |i|
  # 日付を分散（明日から2週間の間、ただし8/14は除外）
  days_offset = (i % 14) + 1
  reserve_date = start_date + days_offset.days
  
  # 8/14は予約データを入れない（goodステータステスト用）
  if reserve_date == Date.new(2025, 8, 14)
    days_offset += 1
    reserve_date = start_date + days_offset.days
  end
  
  # スタッフと時間枠を選択（出勤パターンに合わせて）
  if reserve_date.wday >= 1 && reserve_date.wday <= 5  # 平日
    case i % 3
    when 0  # まさこ（平日全時間）
      staff = staff_masako
      time_slot = [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20].sample
    when 1  # はるか（平日午後）
      staff = staff_haruka
      time_slot = [8, 10, 12, 14, 16, 18, 20].sample
    when 2  # ゆうき（平日午前）
      staff = staff_yuki
      time_slot = [0, 2, 4, 6, 8, 10].sample
    end
  else  # 土日
    case i % 3
    when 0  # まさこ（土日午前のみ）
      staff = staff_masako
      time_slot = [0, 2, 4, 6].sample
    when 1  # はるか（土日全時間）
      staff = staff_haruka
      time_slot = [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20].sample
    when 2  # ゆうき（土日全時間）
      staff = staff_yuki
      time_slot = [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20].sample
    end
  end
  
  customer = customers[i]
  
  sample_reserves << {
    new_staff: staff,
    date: reserve_date,
    start_time_slot: time_slot,
    duration: durations[i],
    customer_name: customer[:name],
    customer_gender: customer[:gender],
    customer_tel: customer[:tel],
    notes: notes_list[i]
  }
end

NewReserve.create!(sample_reserves)

# 8/14のgoodステータス用の予約データは削除
# スタッフの出勤パターンだけでgoodステータスを作成

puts "初期データを作成しました"
puts "スタッフ: #{NewStaff.count}名"
puts "マシン: #{NewMachine.count}種類"
puts "スケジュール: #{NewSchedule.count}件"
puts "出張予定: #{BusinessTrip.count}件"
puts "予約: #{NewReserve.count}件"
puts "対象期間: #{start_date.strftime('%Y/%m/%d')} - #{(start_date + 29.days).strftime('%Y/%m/%d')}"
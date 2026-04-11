namespace :db do
  desc '旧Schedule → 新StaffSchedule 全日付一括同期（今日以降）'
  task sync_staff_schedules: :environment do
    today = Date.current
    puts "=== 旧Schedule → 新StaffSchedule 同期（#{today}以降） ==="

    # 今日以降の旧Scheduleをスタッフ×日付でグループ化
    groups = Schedule.where('schedule_date >= ?', today)
                     .select(:staff_id, :schedule_date).distinct

    synced = 0
    skipped = 0
    created = 0

    groups.each do |group|
      sid  = group.staff_id
      date = group.schedule_date

      spaces = Schedule.where(staff_id: sid, schedule_date: date)
                       .order(:schedule_space)
                       .pluck(:schedule_space)
      next if spaces.empty?

      # 既に新テーブルに同じスタッフ・日付のデータがあるか確認
      existing = StaffSchedule.where(staff_id: sid, date: date)
      if existing.exists?
        # 既存データのカバー範囲と旧データを比較
        old_range = [spaces.first, spaces.last + 0.5]
        new_covers_all = existing.all? do |ss|
          ss.start_time <= space_to_time(old_range[0]) && ss.end_time >= space_to_time(old_range[1])
        end
        if new_covers_all
          skipped += 1
          next
        end
        # カバーしきれていない場合は再作成
        existing.delete_all
      end

      # 連続スロットをまとめる
      ranges = consolidate(spaces)
      ranges.each do |r|
        StaffSchedule.create!(
          staff_id: sid,
          date: date,
          start_time: space_to_time(r[:start]),
          end_time:   space_to_time(r[:end_space])
        )
        created += 1
      end
      synced += 1
    end

    # 同期漏れチェック: 旧にあって新にないスタッフ×日付を表示
    old_pairs = Schedule.where('schedule_date >= ?', today)
                        .select(:staff_id, :schedule_date).distinct
                        .pluck(:staff_id, :schedule_date)
    new_pairs = StaffSchedule.where('date >= ?', today)
                             .select(:staff_id, :date).distinct
                             .pluck(:staff_id, :date)
    missing = old_pairs - new_pairs
    if missing.any?
      puts "  WARNING: 同期漏れ #{missing.size}件"
      missing.each { |sid, d| puts "    staff_id=#{sid}, date=#{d}" }
    end

    puts "  同期: #{synced}件, スキップ: #{skipped}件, レコード作成: #{created}件"
    puts "=== 完了 ==="
  end

  desc '旧Schedule → 新StaffSchedule 同期漏れチェック（DRY RUN）'
  task check_schedule_sync: :environment do
    today = Date.current
    puts "=== 同期漏れチェック（#{today}以降） ==="

    old_groups = Schedule.where('schedule_date >= ?', today)
                         .group(:staff_id, :schedule_date)
                         .count

    missing_count = 0
    mismatch_count = 0

    old_groups.each do |(sid, date), slot_count|
      new_records = StaffSchedule.where(staff_id: sid, date: date)
      if new_records.empty?
        puts "  MISSING: staff_id=#{sid}, date=#{date} (旧#{slot_count}枠, 新0件)"
        missing_count += 1
      else
        # 旧のスロット範囲と新の範囲を比較
        spaces = Schedule.where(staff_id: sid, schedule_date: date)
                         .order(:schedule_space).pluck(:schedule_space)
        old_start = spaces.first
        old_end   = spaces.last + 0.5

        new_start = new_records.minimum(:start_time)
        new_end   = new_records.maximum(:end_time)
        expected_start = space_to_time(old_start)
        expected_end   = space_to_time(old_end)

        if new_start > expected_start || new_end < expected_end
          puts "  MISMATCH: staff_id=#{sid}, date=#{date} 旧#{old_start}-#{old_end} 新#{new_start.strftime('%H:%M')}-#{new_end.strftime('%H:%M')}"
          mismatch_count += 1
        end
      end
    end

    if missing_count == 0 && mismatch_count == 0
      puts "  問題なし"
    else
      puts "  MISSING: #{missing_count}件, MISMATCH: #{mismatch_count}件"
    end
  end

  # --- ヘルパー ---

  def consolidate(spaces)
    ranges = []
    current_start = spaces.first
    current_end = spaces.first

    spaces.each_with_index do |sp, i|
      next if i == 0
      if (sp - current_end - 0.5).abs < 0.01
        current_end = sp
      else
        ranges << { start: current_start, end_space: current_end + 0.5 }
        current_start = sp
        current_end = sp
      end
    end
    ranges << { start: current_start, end_space: current_end + 0.5 }
    ranges
  end

  def space_to_time(space)
    h = space.to_i
    m = ((space - h) * 60).round
    Time.zone.parse('2000-01-01').change(hour: h, min: m)
  end
end

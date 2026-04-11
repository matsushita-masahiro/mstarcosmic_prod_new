namespace :dev do
  desc '開発環境の4/11〜4/17の関連データを削除'
  task clean_week: :environment do
    abort('本番環境では実行できません') if Rails.env.production?

    from = Date.new(2026, 4, 11)
    to   = Date.new(2026, 4, 17)
    range = from..to

    puts "=== 開発環境 #{from} 〜 #{to} のデータ削除 ==="

    # 旧テーブル
    c = Schedule.where(schedule_date: range).delete_all
    puts "  schedules: #{c}件削除"

    c = Reserve.where(reserved_date: range).delete_all
    puts "  reserves: #{c}件削除"

    c = MachineSchedule.where(machine_schedule_date: range).delete_all
    puts "  machine_schedules: #{c}件削除"

    # 新テーブル
    c = StaffSchedule.where(date: range).delete_all
    puts "  staff_schedules: #{c}件削除"

    c = Reservation.where(date: range).delete_all
    puts "  reservations: #{c}件削除"

    c = ServiceUnavailability.where(date: range).delete_all
    puts "  service_unavailabilities: #{c}件削除"

    puts "=== 完了 ==="
  end
end

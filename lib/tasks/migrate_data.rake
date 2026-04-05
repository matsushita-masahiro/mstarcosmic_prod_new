namespace :db do
  namespace :migrate_data do
    desc '新テーブルへデータ移行（並行稼働用）'
    task all: :environment do
      Rake::Task['db:migrate_data:services'].invoke
      Rake::Task['db:migrate_data:staffs'].invoke
      Rake::Task['db:migrate_data:staff_services'].invoke
      Rake::Task['db:migrate_data:staff_schedules'].invoke
      Rake::Task['db:migrate_data:service_unavailabilities'].invoke
      Rake::Task['db:migrate_data:reservations'].invoke
    end

    task services: :environment do
      puts '=== services ==='
      Service.find_or_create_by!(name: 'holistic') do |s|
        s.display_name = 'ホリスティック'
        s.max_concurrent = 2
        s.min_duration = 60
        s.max_duration = 60
        s.active = true
      end
      Service.find_or_create_by!(name: 'seitai') do |s|
        s.display_name = '整体'
        s.max_concurrent = 1
        s.min_duration = 60
        s.max_duration = 60
        s.active = true
      end
      Service.find_or_create_by!(name: 'shinkyu') do |s|
        s.display_name = '鍼灸'
        s.max_concurrent = 1
        s.min_duration = 90
        s.max_duration = 90
        s.active = true
      end
      Service.find_or_create_by!(name: 'wellbeing') do |s|
        s.display_name = 'Wellbeing'
        s.max_concurrent = 0
        s.min_duration = 60
        s.max_duration = 60
        s.active = false
      end
      puts "  services: #{Service.count}件"
    end

    task staffs: :environment do
      puts '=== staffs列更新 ==='
      # まさこ: capacity=1, nomination_fee=2000, can_serve_new=true
      if masako = Staff.find_by(id: 1)
        masako.update!(capacity: 1, nomination_fee: 2000, assignment_type: 'nominatable',
                       new_customer_flag: true)
      end
      # はるか, ゆうき, みほ, ゆか: nominatable, can_serve_new=false
      [2, 3].each do |sid|
        Staff.find_by(id: sid)&.update!(capacity: 1, nomination_fee: 0,
                                         assignment_type: 'nominatable', new_customer_flag: false)
      end
      # ゆか(id=6): holistic担当に変更
      Staff.find_by(id: 6)&.update!(capacity: 1, nomination_fee: 0,
                                     assignment_type: 'nominatable', active_flag: true)
      # まさ（整体）, なおこ（鍼灸）: rotation
      # ※ 新スタッフはseedで作成。ここでは既存スタッフの列更新のみ
      Staff.where.not(id: [0]).where(assignment_type: [nil, '']).update_all(
        capacity: 1, nomination_fee: 0, assignment_type: 'nominatable'
      )
      puts "  staffs更新完了"
    end

    task staff_services: :environment do
      puts '=== staff_services ==='
      StaffService.delete_all
      # holistic担当: まさこ(1), ゆうき(2), はるか(3), ゆか(6), みほ(新規ID)
      holistic_ids = Staff.where(active_flag: true, dismiss_flag: false)
                          .joins('INNER JOIN staff_machine_relations ON staffs.id = staff_machine_relations.staff_id')
                          .where(staff_machine_relations: { machine: 'h' })
                          .where.not(id: 0)
                          .pluck(:id).uniq
      holistic_ids.each do |sid|
        StaffService.find_or_create_by!(staff_id: sid, service: 'holistic')
      end
      # seitai, shinkyu は新スタッフ作成後に手動追加
      puts "  staff_services: #{StaffService.count}件"
    end

    task staff_schedules: :environment do
      puts '=== staff_schedules（schedulesから移行） ==='
      StaffSchedule.delete_all
      count = 0

      # 日付×スタッフでグループ化し、連続スロットを範囲に集約
      Schedule.select(:staff_id, :schedule_date).distinct.each do |group|
        spaces = Schedule.where(staff_id: group.staff_id, schedule_date: group.schedule_date)
                         .order(:schedule_space)
                         .pluck(:schedule_space)
        next if spaces.empty?

        ranges = consolidate_spaces(spaces)
        ranges.each do |r|
          StaffSchedule.create!(
            staff_id: group.staff_id,
            date: group.schedule_date,
            start_time: space_to_time(r[:start]),
            end_time: space_to_time(r[:end] + 0.5) # end_timeは次のスロット開始
          )
          count += 1
        end
      end
      puts "  staff_schedules: #{count}件（旧schedules: #{Schedule.count}件）"
    end

    task service_unavailabilities: :environment do
      puts '=== service_unavailabilities（machine_schedulesから移行） ==='
      ServiceUnavailability.delete_all
      count = 0

      MachineSchedule.select(:machine, :machine_schedule_date).distinct.each do |group|
        service = machine_to_service(group.machine)
        next unless service

        spaces = MachineSchedule.where(machine: group.machine,
                                        machine_schedule_date: group.machine_schedule_date)
                                .order(:machine_schedule_space)
                                .pluck(:machine_schedule_space)
        next if spaces.empty?

        ranges = consolidate_spaces(spaces)
        ranges.each do |r|
          ServiceUnavailability.create!(
            service: service,
            date: group.machine_schedule_date,
            start_time: space_to_time(r[:start]),
            end_time: space_to_time(r[:end] + 0.5)
          )
          count += 1
        end
      end
      puts "  service_unavailabilities: #{count}件"
    end

    task reservations: :environment do
      puts '=== reservations（reservesから移行） ==='
      Reservation.delete_all
      count = 0
      errors = 0

      # root_reserve_idでグループ化
      root_ids = Reserve.where.not(root_reserve_id: nil)
                        .where('root_reserve_id = id')
                        .pluck(:id)
      # root_reserve_idがnilの単独レコードも含める
      solo_ids = Reserve.where(root_reserve_id: nil).pluck(:id)

      (root_ids + solo_ids).each do |rid|
        if rid.in?(root_ids)
          group = Reserve.where(root_reserve_id: rid).order(:reserved_space)
        else
          group = Reserve.where(id: rid)
        end
        next if group.empty?

        first = group.first
        # 休日レコード(user_id=0)はスキップ
        next if first.user_id == 0

        min_space = group.minimum(:reserved_space)
        max_space = group.maximum(:reserved_space)
        duration = group.count * 30
        service = reserve_to_service(first)
        staff_id = first.staff_id == 0 ? nil : first.staff_id

        begin
          Reservation.create!(
            user_id: first.user_id,
            staff_id: staff_id,
            service: service,
            date: first.reserved_date,
            start_time: space_to_time(min_space),
            end_time: space_to_time(max_space + 0.5),
            duration: duration,
            is_new_customer: first.new_customer || false,
            notes: first.remarks,
            status: 0,
            group_id: SecureRandom.uuid,
            created_at: first.created_at,
            updated_at: first.updated_at
          )
          count += 1
        rescue => e
          errors += 1
          puts "  ERROR reserve##{rid}: #{e.message}"
        end
      end
      puts "  reservations: #{count}件移行, #{errors}件エラー（旧reserves root: #{root_ids.size + solo_ids.size}件）"
    end

    # --- ヘルパーメソッド ---

    def consolidate_spaces(spaces)
      ranges = []
      current_start = spaces.first
      current_end = spaces.first

      spaces.each_with_index do |sp, i|
        next if i == 0
        if (sp - current_end - 0.5).abs < 0.01
          current_end = sp
        else
          ranges << { start: current_start, end: current_end }
          current_start = sp
          current_end = sp
        end
      end
      ranges << { start: current_start, end: current_end }
      ranges
    end

    def space_to_time(space)
      h = space.to_i
      m = ((space - h) * 60).round
      format('%02d:%02d', h, m)
    end

    def machine_to_service(machine)
      case machine
      when 'h' then 'holistic'
      when 'w' then 'wellbeing'
      else nil
      end
    end

    def reserve_to_service(reserve)
      case reserve.machine
      when 'h' then 'holistic'
      when 'w' then 'wellbeing'
      when 'e' then 'esthe'
      when 'b' then 'seitai'
      when 'o'
        case reserve.staff_id
        when 1 then 'sanmei'
        when 5 then 'choumomi'
        when 8 then 'seitai'
        else 'other'
        end
      else 'other'
      end
    end
  end
end

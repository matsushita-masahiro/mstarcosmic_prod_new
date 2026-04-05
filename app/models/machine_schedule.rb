class MachineSchedule < ApplicationRecord
  after_save :sync_to_service_unavailabilities
  after_destroy :sync_to_service_unavailabilities

  private

  def sync_to_service_unavailabilities
    service = case machine
              when 'h' then 'holistic'
              when 'w' then 'wellbeing'
              else return
              end

    date = machine_schedule_date
    # この日のこのサービスの全unavailabilityを再構築
    ServiceUnavailability.where(service: service, date: date).destroy_all

    spaces = MachineSchedule.where(machine: machine, machine_schedule_date: date)
                            .order(:machine_schedule_space)
                            .pluck(:machine_schedule_space)
    return if spaces.empty?

    # 連続スロットを範囲に集約
    ranges = []
    start_sp = spaces.first
    prev_sp = spaces.first
    spaces.each_with_index do |sp, i|
      next if i == 0
      if (sp - prev_sp - 0.5).abs < 0.01
        prev_sp = sp
      else
        ranges << [start_sp, prev_sp]
        start_sp = sp
        prev_sp = sp
      end
    end
    ranges << [start_sp, prev_sp]

    ranges.each do |s, e|
      h = s.to_i; m = ((s - h) * 60).round
      eh = (e + 0.5).to_i; em = (((e + 0.5) - eh) * 60).round
      ServiceUnavailability.create!(
        service: service,
        date: date,
        start_time: format('%02d:%02d', h, m),
        end_time: format('%02d:%02d', eh, em),
        reason: 'business_trip'
      )
    end
  end
end

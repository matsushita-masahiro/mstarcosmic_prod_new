namespace :staff do
  desc "staff_machine_relationsからstaff_servicesを一括同期"
  task sync_services: :environment do
    StaffMachineRelation.where.not(staff_id: 0).pluck(:staff_id).uniq.each do |sid|
      machines = StaffMachineRelation.where(staff_id: sid).pluck(:machine)
      services = machines.map { |m| %w[h stem w].include?(m) ? 'holistic' : 'seitai' }.uniq
      StaffService.where(staff_id: sid).delete_all
      services.each { |s| StaffService.create!(staff_id: sid, service: s) }
      puts "staff_id=#{sid}: #{services.join(', ')}"
    end
    puts "同期完了"
  end
end

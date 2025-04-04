module MachineSchedulesHelper
    
      # 出張用メソッド（出張中に渋谷のmachine台数が減る）
      def machine_schedule(date, space, machine)
        if MachineSchedule.find_by(machine_schedule_date: date, machine_schedule_space: space, machine: machine)
          return 1
        else
          return 0
        end
      end
      
end

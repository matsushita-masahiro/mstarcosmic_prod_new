class CreateMachineSchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :machine_schedules do |t|
      t.date "machine_schedule_date"
      t.float "machine_schedule_space"
      t.string "machine"      
      t.timestamps
    end
  end
end

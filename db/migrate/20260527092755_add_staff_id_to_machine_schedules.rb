class AddStaffIdToMachineSchedules < ActiveRecord::Migration[8.0]
  def change
    add_column :machine_schedules, :staff_id, :integer
  end
end

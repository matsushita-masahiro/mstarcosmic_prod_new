class AddColStaffidToSchedule < ActiveRecord::Migration[8.0]
  def change
    add_reference :schedules, :staff, foreign_key: true 
  end
end

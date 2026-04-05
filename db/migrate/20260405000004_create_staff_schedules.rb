class CreateStaffSchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_schedules do |t|
      t.bigint :staff_id, null: false
      t.date :date, null: false
      t.time :start_time, null: false
      t.time :end_time, null: false
      t.timestamps
    end

    add_index :staff_schedules, [:staff_id, :date, :start_time], unique: true
    add_index :staff_schedules, :date
    add_foreign_key :staff_schedules, :staffs
  end
end

class CreateNewSchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :new_schedules do |t|
        t.integer :staff_id, null: false
        t.date :date
        t.integer :time_slot
        t.boolean :working
        t.timestamps
      end
      add_index :new_schedules, :staff_id
  end
end

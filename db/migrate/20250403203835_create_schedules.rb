class CreateSchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :schedules do |t|
      t.references :user, foreign_key: true
      t.date   :schedule_date
      t.float  :schedule_space
      t.string :schedule_type      
      t.timestamps
    end
  end
end

class CreateReservations < ActiveRecord::Migration[8.0]
  def change
    create_table :reservations do |t|
      t.bigint :user_id, null: false
      t.bigint :staff_id
      t.string :service, limit: 20, null: false
      t.date :date, null: false
      t.time :start_time, null: false
      t.time :end_time, null: false
      t.integer :duration, null: false
      t.boolean :is_new_customer, null: false, default: false
      t.text :notes
      t.integer :status, null: false, default: 0
      t.string :group_id, limit: 36
      t.timestamps
    end

    add_index :reservations, :date
    add_index :reservations, [:staff_id, :date]
    add_index :reservations, :user_id
    add_foreign_key :reservations, :users
    add_foreign_key :reservations, :staffs
  end
end

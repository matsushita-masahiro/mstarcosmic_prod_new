class CreateNewReserves < ActiveRecord::Migration[8.0]
  def change
    create_table :new_reserves do |t|
      t.integer :user_id
      t.integer :staff_id, null: false
      t.date :date
      t.integer :start_time_slot
      t.integer :duration
      t.text :notes
      t.string :customer_name
      t.integer :customer_gender
      t.string :customer_tel

      t.timestamps
    end

    add_index :new_reserves, :staff_id, name: "index_new_reserves_on_staff_id"
    add_index :new_reserves, :user_id, name: "index_new_reserves_on_user_id"
  end
end

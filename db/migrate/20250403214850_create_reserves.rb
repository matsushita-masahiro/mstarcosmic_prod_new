class CreateReserves < ActiveRecord::Migration[8.0]
  def change
    create_table :reserves do |t|
      t.integer "user_id"
      t.date "reserved_date"
      t.text "remarks"
      t.float "reserved_space"
      t.integer "root_reserve_id"
      t.integer "staff_id"
      t.string "machine"
      t.boolean "new_customer", default: false, null: false      
      t.timestamps
    end
  end
end

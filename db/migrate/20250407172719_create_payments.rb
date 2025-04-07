class CreatePayments < ActiveRecord::Migration[8.0]
  def change
    create_table :payments do |t|
      t.integer "user_id"
      t.integer "price"
      t.string "pay_type"
      t.text "remarks"      
      t.timestamps
    end
  end
end

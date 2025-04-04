class CreateCoupons < ActiveRecord::Migration[8.0]
  def change
    create_table :coupons do |t|
      t.integer "payment_id"
      t.string "status"
      t.integer "order_number"
      t.string "remarks"      
      t.timestamps
    end
  end
end

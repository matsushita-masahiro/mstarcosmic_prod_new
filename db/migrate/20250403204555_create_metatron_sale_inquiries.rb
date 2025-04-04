class CreateMetatronSaleInquiries < ActiveRecord::Migration[8.0]
  def change
    create_table :metatron_sale_inquiries do |t|
      t.string "name"
      t.string "name_kana"
      t.string "phone"
      t.string "email"
      t.integer "postcode"
      t.integer "prefecture_code"
      t.string "address_city"
      t.boolean "trial_flag", default: false, null: false
      t.boolean "buy_consult_flag", default: false, null: false
      t.boolean "hp_consult_flag", default: false, null: false
      t.text "content"      
      t.timestamps
    end
  end
end

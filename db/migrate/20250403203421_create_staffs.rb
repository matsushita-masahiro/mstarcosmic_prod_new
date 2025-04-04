class CreateStaffs < ActiveRecord::Migration[8.0]
  def change
    create_table :staffs do |t|
      t.integer "user_id"
      t.string "name"
      t.boolean "active_flag", default: false, null: false
      t.string "name_kanji"
      t.boolean "dismiss_flag", default: false, null: false
      t.boolean "new_customer_flag", default: false, null: false
      t.timestamps
    end
  end
end

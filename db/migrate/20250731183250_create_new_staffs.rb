class CreateNewStaffs < ActiveRecord::Migration[8.0]
  def change
    create_table :new_staffs do |t|
      t.string "name"
      t.integer "staff_type"
      t.boolean "active"
      t.timestamps
    end
  end
end

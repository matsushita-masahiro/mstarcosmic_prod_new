class CreateStaffServices < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_services do |t|
      t.bigint :staff_id, null: false
      t.string :service, limit: 20, null: false
      t.timestamps
    end

    add_index :staff_services, [:staff_id, :service], unique: true
    add_foreign_key :staff_services, :staffs
  end
end

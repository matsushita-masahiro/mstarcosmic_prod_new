class AddColumnsToStaffs < ActiveRecord::Migration[8.0]
  def change
    add_column :staffs, :capacity, :integer, null: false, default: 1
    add_column :staffs, :nomination_fee, :integer, null: false, default: 0
    add_column :staffs, :assignment_type, :string, limit: 20, null: false, default: 'nominatable'
  end
end

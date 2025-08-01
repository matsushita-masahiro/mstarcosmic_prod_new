class RemoveStaffIdFromNewSchedulesAndAddNewStaffReference < ActiveRecord::Migration[8.0]
  def change
    # 既存のstaff_idカラムとそのインデックスを削除
    remove_index :new_schedules, :staff_id if index_exists?(:new_schedules, :staff_id)
    remove_column :new_schedules, :staff_id, :integer
    
    # new_staffsテーブルへの参照を追加
    add_reference :new_schedules, :new_staff, null: false, foreign_key: true, index: true
  end
end

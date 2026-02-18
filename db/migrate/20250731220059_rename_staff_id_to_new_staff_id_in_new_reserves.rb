class RenameStaffIdToNewStaffIdInNewReserves < ActiveRecord::Migration[8.0]
  def change
    # インデックスを削除
    remove_index :new_reserves, :staff_id if index_exists?(:new_reserves, :staff_id)
    
    # カラム名を変更
    rename_column :new_reserves, :staff_id, :new_staff_id
    
    # 新しいインデックスを追加
    add_index :new_reserves, :new_staff_id
    
    # 外部キー制約を追加
    add_foreign_key :new_reserves, :new_staffs, column: :new_staff_id
  end
end

class RenameMatchineIdToNewMachineIdInBusinessTrips < ActiveRecord::Migration[8.0]
  def change
    # インデックスを削除
    remove_index :business_trips, :machine_id if index_exists?(:business_trips, :machine_id)
    
    # カラム名を変更
    rename_column :business_trips, :machine_id, :new_machine_id
    
    # 新しいインデックスを追加
    add_index :business_trips, :new_machine_id
    
    # 外部キー制約を追加
    add_foreign_key :business_trips, :new_machines, column: :new_machine_id
  end
end

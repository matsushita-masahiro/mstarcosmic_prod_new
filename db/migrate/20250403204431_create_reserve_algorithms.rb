class CreateReserveAlgorithms < ActiveRecord::Migration[8.0]
  def change
    create_table :reserve_algorithms do |t|
      t.integer "num_staffs_for_new"
      t.integer "num_staffs_for_nonnew"
      t.integer "num_of_machines"
      t.integer "num_of_reseve_for_new"
      t.integer "num_of_reseve_for_old"
      t.integer "available_for_new"
      t.integer "available_for_old"     
      t.timestamps
    end
  end
end

class CreateNewMachines < ActiveRecord::Migration[8.0]
  def change
    create_table :new_machines do |t|
      t.string "name"
      t.integer "total_count"
      t.timestamps
    end
  end
end

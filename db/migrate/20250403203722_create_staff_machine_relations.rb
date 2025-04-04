class CreateStaffMachineRelations < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_machine_relations do |t|
      t.references :staff, foreign_key: true
      t.string :machine      
      t.timestamps
    end
  end
end

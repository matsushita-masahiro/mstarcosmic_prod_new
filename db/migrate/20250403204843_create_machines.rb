class CreateMachines < ActiveRecord::Migration[8.0]
  def change
    create_table :machines do |t|
      t.string "name"
      t.integer "number_of_machine"
      t.string "short_word"      
      t.timestamps
    end
  end
end

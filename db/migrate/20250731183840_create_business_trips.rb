class CreateBusinessTrips < ActiveRecord::Migration[8.0]
  def change
    create_table :business_trips do |t|
      t.integer :machine_id, null: false
      t.date :date
      t.integer :time_slot

      t.timestamps
    end

    add_index :business_trips, :machine_id, name: "index_business_trips_on_machine_id"
  end
end

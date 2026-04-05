class CreateServiceUnavailabilities < ActiveRecord::Migration[8.0]
  def change
    create_table :service_unavailabilities do |t|
      t.string :service, limit: 20, null: false
      t.date :date, null: false
      t.time :start_time, null: false
      t.time :end_time, null: false
      t.string :reason, limit: 50, default: 'business_trip'
      t.timestamps
    end

    add_index :service_unavailabilities, :date
    add_index :service_unavailabilities, [:service, :date]
  end
end

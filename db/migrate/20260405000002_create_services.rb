class CreateServices < ActiveRecord::Migration[8.0]
  def change
    create_table :services do |t|
      t.string :name, limit: 50, null: false
      t.string :display_name, limit: 50, null: false
      t.integer :max_concurrent, null: false, default: 1
      t.integer :min_duration, null: false, default: 30
      t.integer :max_duration, null: false, default: 60
      t.bigint :fixed_staff_id
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :services, :name, unique: true
    add_foreign_key :services, :staffs, column: :fixed_staff_id
  end
end

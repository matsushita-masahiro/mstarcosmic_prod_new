class CreateKarteAccessLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :karte_access_logs do |t|
      t.references :actor,   null: false, foreign_key: { to_table: :users }
      t.references :patient, null: false, foreign_key: { to_table: :users }
      t.string :action,      null: false
      t.string :resource_type
      t.bigint :resource_id
      t.string :ip_address
      t.string :user_agent
      t.datetime :created_at, null: false
    end
    add_index :karte_access_logs, %i[patient_id created_at]
    add_index :karte_access_logs, %i[actor_id created_at]
  end
end

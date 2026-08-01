class CreateIntakeSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :intake_sessions do |t|
      t.references :user,   null: false, foreign_key: true
      t.references :issuer, null: false, foreign_key: { to_table: :users }
      t.string   :token_digest, null: false
      t.datetime :expires_at,   null: false
      t.datetime :completed_at
      t.datetime :revoked_at
      t.string :issuer_ip
      t.string :client_ip
      t.string :client_user_agent
      t.timestamps
    end
    add_index :intake_sessions, :token_digest, unique: true
    add_index :intake_sessions, :expires_at
  end
end

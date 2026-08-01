class CreateConsents < ActiveRecord::Migration[8.0]
  def change
    create_table :consents do |t|
      t.references :user,             null: false, foreign_key: true
      t.references :consent_document, null: false, foreign_key: true
      t.references :intake_session,   foreign_key: true
      t.datetime :agreed_at, null: false
      t.string   :signer_name
      t.integer  :signer_relation, default: 0
      t.jsonb    :signature_strokes
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end
    add_index :consents, %i[user_id consent_document_id]
    add_index :consents, :agreed_at
  end
end

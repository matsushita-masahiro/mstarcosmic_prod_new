class CreateConsentDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :consent_documents do |t|
      t.string :version, null: false
      t.string :title,   null: false
      t.text   :body,    null: false
      t.string :body_digest, null: false
      t.datetime :published_at
      t.datetime :archived_at
      t.timestamps
    end
    add_index :consent_documents, :version, unique: true
    add_index :consent_documents, :published_at
  end
end

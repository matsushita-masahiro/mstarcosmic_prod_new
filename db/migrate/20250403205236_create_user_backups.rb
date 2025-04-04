class CreateUserBackups < ActiveRecord::Migration[8.0]
  def change
    create_table :user_backups do |t|
      t.string "email"
      t.string "encrypted_password"
      t.string "reset_password_token"
      t.datetime "reset_password_sent_at"
      t.datetime "remember_created_at"
      t.string "confirmation_token"
      t.datetime "confirmed_at"
      t.datetime "confirmation_sent_at"
      t.string "unconfirmed_email"
      t.string "name_kana"
      t.string "name"
      t.string "tel"
      t.date "birthday"
      t.string "introducer"
      t.string "gender"
      t.text "remarks"
      t.string "membership_number"
      t.string "user_type"
      t.string "abo"      
      t.timestamps
    end
  end
end

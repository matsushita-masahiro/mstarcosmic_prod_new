class CreatePatientProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :patient_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :name_kana
      t.string :name_roman
      t.date    :birth_date
      t.integer :sex
      t.integer :blood_type
      t.string :postal_code
      t.string :prefecture
      t.string :city
      t.string :address_line
      t.string :building
      t.string :phone
      t.string :nearest_station
      t.integer :referral_source
      t.string  :referral_detail
      t.timestamps
    end
    add_index :patient_profiles, :postal_code
    add_index :patient_profiles, :name_kana
  end
end

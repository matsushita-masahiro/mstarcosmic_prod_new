# users テーブルに既存の項目と重複するカラムを patient_profiles から削除する。
#
# users 側に既にある項目:
#   name / name_kana / tel / birthday / gender / membership_number / remarks
# これらを patient_profiles にも持つと二重管理になり、どちらが正か分からなくなる。
#
# なお users.abo は血液型カラムだが、実データが "abo"(476件) / "other"(434件) で
# A/B/O/AB の区別として機能していないため、blood_type は patient_profiles 側で管理する。
class CleanupPatientProfiles < ActiveRecord::Migration[8.0]
  def up
    remove_column :patient_profiles, :name_kana
    remove_column :patient_profiles, :birth_date
    remove_column :patient_profiles, :sex
    remove_column :patient_profiles, :phone
  end

  def down
    add_column :patient_profiles, :name_kana, :string
    add_column :patient_profiles, :birth_date, :date
    add_column :patient_profiles, :sex, :integer
    add_column :patient_profiles, :phone, :string
    add_index  :patient_profiles, :name_kana
  end
end

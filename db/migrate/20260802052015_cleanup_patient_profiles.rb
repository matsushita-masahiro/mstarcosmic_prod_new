# users テーブルに既存の項目と重複するカラムを patient_profiles から削除する。
#
# users 側に既にある項目:
#   name / name_kana / tel / birthday / gender / membership_number / remarks
# これらを patient_profiles にも持つと二重管理になり、どちらが正か分からなくなる。
#
# なお users.abo は血液型カラムだが、実データが "abo"(476件) / "other"(434件) で
# A/B/O/AB の区別として機能していないため、blood_type は patient_profiles 側で管理する。
#
# ※注記（後日訂正）─────────────────────────────
# 直上2行の前提は誤り。users.abo は血液型カラムではなく、
# Amway ABO（Amway Business Owner）会員かどうかの判定カラムである。
# app/views/users/edit.html.erb の UI が「ABOの方 / ABO以外」の二択であること、
# 本番の分布が "other" 727件 / "abo" 587件 と約45:55で、血液型の分布とは
# 似ても似つかないことから確認した（上記の 476/434 は staging の数字）。
#
# したがって「abo が血液型として壊れているから blood_type を patient_profiles に置く」
# という因果は成り立たない。この段落は当時の判断の記録として残すが、
# 根拠としては使わないこと。
#
# 適用済みのマイグレーションのため本文は書き換えていない。
# patient_profiles.blood_type は未使用のまま本番0件で、別のマイグレーションで削除する。
# ────────────────────────────────────────
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

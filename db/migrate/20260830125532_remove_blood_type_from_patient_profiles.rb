# 未使用の patient_profiles.blood_type を削除する。
#
# 血液型は users.blood_type に持つことにしたため
# （20260830125530）、残すと血液型が2箇所にある状態を新たに作る。
# それはまさに 20260802052015 が避けようとした二重管理にあたる。
#
# 消してよい根拠:
#   - 本番・staging とも patient_profiles は 0 件
#   - 参照は PatientProfile の enum 定義 1行だけで、ビュー・コントローラ・
#     検索条件・シード・rake タスクのいずれからも読まれていない
#   - スタッフが入力する UI も無い（karte のルートは index / show のみ）
#
# patient_profiles テーブル自体と他のカラム（name_roman / 住所 /
# nearest_station / referral_source / referral_detail）には触らない。
# それらを消すかどうかは血液型とは別の判断になる。
class RemoveBloodTypeFromPatientProfiles < ActiveRecord::Migration[8.0]
  def change
    remove_column :patient_profiles, :blood_type, :integer
  end
end

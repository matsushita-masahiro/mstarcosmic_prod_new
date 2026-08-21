# 患者を削除できるようにするための外部キーの緩和。
#
# どちらも「消えた側を指していた参照」を nil に落とすだけで、記録本体は残る。
# Rails の dependent: :nullify ではなく DB の on_delete を使うのは、
# runner や SQL 直叩きなど Rails を経由しない削除でも効かせるため。
#
# 【previous_id は変更しない】
# medical_questionnaires.previous_id（訂正の鎖）は restrict のままにする。
# 訂正版が指している版を消せないのは正しい。記録の整合性そのもの。
class NullifyQuestionnaireBackReferences < ActiveRecord::Migration[8.0]
  def up
    # intake_sessions は30分で失効する入場券。指していた問診票が消えたあとに
    # 残す価値が無い。restrict のままだと「訂正QRを発行しただけで、その患者を
    # 二度と削除できなくなる」ため、時間が経つほど消せない患者が増えていた。
    remove_foreign_key :intake_sessions, column: :target_questionnaire_id
    add_foreign_key :intake_sessions, :medical_questionnaires,
                    column: :target_questionnaire_id, on_delete: :nullify

    # 誰が確認したかは失われるが、問診票そのものは残る。
    remove_foreign_key :medical_questionnaires, column: :reviewed_by_id
    add_foreign_key :medical_questionnaires, :users,
                    column: :reviewed_by_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :intake_sessions, column: :target_questionnaire_id
    add_foreign_key :intake_sessions, :medical_questionnaires,
                    column: :target_questionnaire_id

    remove_foreign_key :medical_questionnaires, column: :reviewed_by_id
    add_foreign_key :medical_questionnaires, :users, column: :reviewed_by_id
  end
end

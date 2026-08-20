# 問診票の確認署名。
#
# 列の構成は consents に合わせている。同じ来店の同意書署名と問診票署名を
# 突き合わせる場面（家族の代筆かどうかを確かめる等）で、
# 列名や値の対応表を挟まずに比べられるようにするため。
#
# 既存レコード（本番11件・staging 12件）は signed_at が nil になる。
# 遡って署名させることはできないので、「署名の運用開始前に提出されたもの」
# として表示側で区別する（MedicalQuestionnaire#signed? / カルテの表示）。
class AddSignatureToMedicalQuestionnaires < ActiveRecord::Migration[8.0]
  def change
    add_column :medical_questionnaires, :signed_at, :datetime
    add_column :medical_questionnaires, :signer_name, :string
    add_column :medical_questionnaires, :signer_relation, :integer, default: 0
    add_column :medical_questionnaires, :signature_strokes, :jsonb
    add_column :medical_questionnaires, :ip_address, :string
    add_column :medical_questionnaires, :user_agent, :string

    # 「署名のあるもの／無いもの」を数えたり一覧するための索引。
    # consents の agreed_at と同じ位置づけ。
    add_index :medical_questionnaires, :signed_at
  end
end

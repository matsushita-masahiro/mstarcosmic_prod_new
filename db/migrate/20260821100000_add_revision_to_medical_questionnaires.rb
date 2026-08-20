# 問診票の訂正（版管理）。
#
# 提出済みの問診票を修正するとき、上書きせず新しい版を作る。
# 病歴・服薬・ペースメーカーの有無で施術可否を判断しているため、
# 上書きすると「当時どう判断したか」の根拠が消える。
# 紙のカルテで修正液を使わず二重線を引くのと同じ考え方。
#
# 差分だけを持って元を書き換える方式は採らない。記録漏れやバグがあれば
# 元の内容が永久に戻せなくなる。訂正版も完全なレコードとして保存し、
# 差分は表示のときに計算する。
class AddRevisionToMedicalQuestionnaires < ActiveRecord::Migration[8.0]
  def change
    # 前版への参照。独立した提出は nil。
    # on_delete は既定（restrict）。訂正版が指している版を消せないのは正しい。
    # ユーザ削除時は has_one 側の dependent: :nullify が先に外す。
    add_reference :medical_questionnaires, :previous,
                  foreign_key: { to_table: :medical_questionnaires }, null: true

    # その系列の中で何版目か。独立した提出は 1。
    add_column :medical_questionnaires, :revision, :integer, null: false, default: 1

    # 訂正理由（任意）。何を直したかをスタッフが後から読むためのもの。
    add_column :medical_questionnaires, :revision_note, :text
  end
end

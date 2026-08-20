# 入場トークンの用途。
#
# 新規記入（initial）と訂正（revision）で入口の行き先が変わる。
# 既存のレコードはすべて initial になる。
class AddPurposeToIntakeSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :intake_sessions, :purpose, :integer, null: false, default: 0

    # 訂正の対象。initial では nil。
    add_reference :intake_sessions, :target_questionnaire,
                  foreign_key: { to_table: :medical_questionnaires }, null: true
  end
end

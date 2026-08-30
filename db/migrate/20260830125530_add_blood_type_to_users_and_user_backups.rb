# 血液型の保存先。問診票で聞き、users に持つ。
#
# patient_profiles.blood_type は使わない。本番・staging とも patient_profiles は
# 0件で、全患者が has_one 無しの状態にある。そちらに置くと参照のたびに
# patient_profile&. の nil 分岐を書くことになり、これは実際に500を踏んだ形
# （20260802052015 で削除済みのカラムを &. 越しに参照していた事故）と同じ。
# 患者の恒久属性は users に集約する、という 20260802052015 の方針にも合う。
#
# 値は問診票の回答をそのまま入れる（"a" / "b" / "o" / "ab" / "unknown"）。
# users.gender が "female" → "f" の変換層を持っているのは、gender が問診票より
# 古く語彙が違うからで、今回は新設なので変換を作らない。作らなければズレない。
#
# NULL は「まだ訊いていない」。"unknown" は「患者が不明と答えた」。
# この2つは別物で、区別しないと来店のたびに同じことを聞くことになる。
#
# インデックスは張らない。血液型で検索する要件が無く、
# カーディナリティも5値しかないため効かない。必要になってから追加する。
#
# 【users と user_backups を1つのマイグレーションで足している理由】
# user_backups は users の複製先で、UsersController#backup_users が
# カラムを1行ずつ手で写している。テーブルとコピー処理のどちらかが漏れると、
# バックアップから静かに欠ける。別々のマイグレーションにすると片方だけ
# 適用された状態を作れてしまうので、まとめて不可分にしている。
class AddBloodTypeToUsersAndUserBackups < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :blood_type, :string
    add_column :user_backups, :blood_type, :string
  end
end

# 患者の追加情報。
#
# 【重要】氏名・カナ・電話番号・生年月日・性別は users テーブルにある。
# ここでは users に無い項目のみを管理する。二重管理を避けるため、
# 表示・検索は必ず users 側を参照すること。
class PatientProfile < ApplicationRecord
  belongs_to :user

  # 血液型はここには無い。users.blood_type にある（20260830125530）。
  # 患者の恒久属性は users に集約する方針（20260802052015）に合わせ、
  # 未使用だった blood_type カラムは 20260830125532 で削除した。
  enum :referral_source, { introduction: 0, hp: 1, other: 2 }, prefix: true

  validates :postal_code, format: { with: /\A\d{7}\z/, allow_blank: true }

  before_validation :normalize_postal_code

  def full_address
    [prefecture, city, address_line, building].compact_blank.join(" ")
  end

  private

  def normalize_postal_code
    self.postal_code = postal_code&.gsub(/[^0-9]/, "")&.presence
  end
end

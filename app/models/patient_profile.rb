# 患者の追加情報。
#
# 【重要】氏名・カナ・電話番号・生年月日・性別は users テーブルにある。
# ここでは users に無い項目のみを管理する。二重管理を避けるため、
# 表示・検索は必ず users 側を参照すること。
class PatientProfile < ApplicationRecord
  belongs_to :user

  # users.abo は "abo"/"other" しか入っておらず血液型として機能していないため、
  # 血液型はこちらで管理する。
  enum :blood_type, { a: 0, b: 1, o: 2, ab: 3, unknown: 4 }, prefix: true
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

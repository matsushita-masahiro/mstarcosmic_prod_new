# 患者の追加情報。
#
# 【重要】氏名・カナ・電話番号・生年月日・性別は users テーブルにある。
# ここでは users に無い項目のみを管理する。二重管理を避けるため、
# 表示・検索は必ず users 側を参照すること。
class PatientProfile < ApplicationRecord
  belongs_to :user

  # 血液型はここで管理する。
  #
  # 【注意】users.abo は血液型ではない。Amway ABO（Amway Business Owner）会員か
  # どうかの判定カラムで、値も "abo" / "other" の二択
  # （app/views/users/edit.html.erb の「ABOの方 / ABO以外」がその UI）。
  # 名前が似ているだけで血液型とは無関係なので、血液型の保存先を検討するときに
  # abo を候補に入れないこと。以前このカラムを「壊れた血液型カラム」と誤認した
  # 記述があり、db/migrate/20260802052015_cleanup_patient_profiles.rb に
  # その訂正を残してある。
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

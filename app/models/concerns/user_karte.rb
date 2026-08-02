# app/models/concerns/user_karte.rb
#
# User にカルテ関連の振る舞いを追加する。
# 既存の User モデルに include して使う:
#   class User < ApplicationRecord
#     include UserKarte
#     ...
#   end
module UserKarte
  extend ActiveSupport::Concern

  # gender の実データは "f"(667) / "m"(196) / nil(46) / "男性"(1)。
  # 表記ゆれがあるため複数の値を受ける。
  FEMALE_VALUES = %w[f female woman 女 女性].freeze
  MALE_VALUES   = %w[m male man 男 男性].freeze

  included do
    has_one  :patient_profile, dependent: :destroy
    has_many :medical_questionnaires, dependent: :destroy
    has_many :consents, dependent: :destroy
    has_many :intake_sessions, dependent: :destroy
  end

  # 会員番号（紙運用との突合のためゼロ埋め表示）
  def karte_member_no = format("%06d", id)

  def female? = FEMALE_VALUES.include?(gender.to_s.downcase)
  def male?   = MALE_VALUES.include?(gender.to_s.downcase)

  # 性別が判別できるか。できない場合は問診票の冒頭で聞く。
  def gender_known? = female? || male?

  def gender_label
    return "女性" if female?
    return "男性" if male?
    "未登録"
  end

  def age(on: Date.current)
    return nil if birthday.blank?
    years = on.year - birthday.year
    years -= 1 if ([on.month, on.day] <=> [birthday.month, birthday.day]) == -1
    years
  end

  def birthday_display
    birthday&.strftime("%Y/%m/%d")
  end

  def latest_questionnaire
    medical_questionnaires.status_submitted.latest_first.first
  end

  # 初診日 = 最初の同意署名日。無ければ最初の問診票提出日。
  def first_visit_at
    consents.minimum(:agreed_at) || medical_questionnaires.minimum(:submitted_at)
  end
end

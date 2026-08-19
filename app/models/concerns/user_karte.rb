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

  # カルテ対象外の user_type（1=管理者 / 10=施術スタッフ）
  # 患者一覧の除外条件と、施術メモの担当者候補の両方で使う。
  STAFF_USER_TYPES = %w[1 10].freeze

  included do
    has_one  :patient_profile, dependent: :destroy
    has_many :medical_questionnaires, dependent: :destroy
    has_many :consents, dependent: :destroy
    has_many :intake_sessions, dependent: :destroy
    has_many :treatment_notes, dependent: :destroy

    scope :karte_staff, -> { where(user_type: STAFF_USER_TYPES).order(:id) }
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

  # 下書き以外の最新1件。reviewed（スタッフが確認済みにした版）も含む。
  # status_submitted で絞ると、確認した問診票ほど最新版から漏れる。
  def latest_questionnaire
    medical_questionnaires.confirmed.latest_first.first
  end

  # 一覧用。scope を使うと includes 済みでも行ごとにクエリが出るため、
  # 読み込み済みの関連から Ruby 側で絞る。
  #
  # 比較を配列にして id を第2キーにしている。提出が同時刻の2件では
  # submitted_at だけでは決まらず、latest_first（SQL 側）が id DESC で選ぶ版と
  # 食い違って、一覧と詳細で別の問診票が出てしまうため。
  # 名前に submitted とあるが reviewed も含む（下書き以外の最新）。
  def latest_submitted_questionnaire
    medical_questionnaires.reject(&:status_draft?)
                          .max_by { |q| [q.submitted_at || Time.at(0), q.id] }
  end

  # 初診日 = 最初の同意署名日。無ければ最初の問診票提出日。
  def first_visit_at
    consents.minimum(:agreed_at) || medical_questionnaires.minimum(:submitted_at)
  end
end

# 来店ごとの施術メモ。手書きカルテの置き換え。
#
# 記録としての性質上、担当スタッフの User が退職などで消えても
# 「誰が施術したか」は残す必要があるため、担当者名を author_name に控える。
class TreatmentNote < ApplicationRecord
  belongs_to :user
  belongs_to :author, class_name: "User", optional: true

  validates :visited_on, presence: true
  validates :author_name, presence: true
  validate  :body_or_ticket_present

  # 担当が付け替わったときだけ控え直す。
  # 担当者の User が消えたとき（author_id が nil になるとき）は控えを残す。
  before_validation :remember_author_name, if: -> { author_id.present? && author_id_changed? }

  scope :latest_first, -> { order(visited_on: :desc, id: :desc) }

  # メモ本文と券欄をまとめて検索する。
  # 検索語の % や _ は LIKE のワイルドカードではなく文字として扱う。
  #
  # ILIKE なのはカルテ一覧の検索（氏名・カナ・電話）に合わせるため。
  # 券名もメモ本文も自由記入で "VIP"/"vip" のような揺れが避けられず、
  # 同じ画面で片方だけ大小を区別すると使う側が混乱する。
  scope :search, ->(term) {
    next all if term.blank?

    pattern = "%#{sanitize_sql_like(term.to_s.strip)}%"
    where("body ILIKE :q OR ticket ILIKE :q", q: pattern)
  }

  private

  def remember_author_name
    self.author_name = author&.name
  end

  def body_or_ticket_present
    return if body.present? || ticket.present?

    errors.add(:base, "メモか券のどちらかを入力してください")
  end
end

class MedicalQuestionnaire < ApplicationRecord
  include MedicalQuestionnaireFlags

  belongs_to :user
  belongs_to :intake_session, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  has_many :handwriting_entries, dependent: :destroy
  has_many :body_marks, dependent: :destroy

  accepts_nested_attributes_for :handwriting_entries, :body_marks, allow_destroy: true

  enum :status, { draft: 0, submitted: 1, reviewed: 2 }, prefix: true

  validates :form_version, presence: true
  validates :pregnancy_weeks, numericality: { in: 1..45 }, allow_nil: true

  before_save :promote_flags_from_answers

  # 第2キーに id を必ず付ける。提出が同時刻の2件（訂正の再提出や、
  # まとめて取り込んだ紙カルテ）では COALESCE の値が並び、
  # これが無いと Postgres が返す順を保証しない。
  # カルテ一覧の「施術不可 / 要確認」バッジと、カルテ詳細の警告バナー・
  # 内容パネルの既定は、どれも finalized の先頭1件を見る。
  # 順序が揺れると古い版の判定が画面に出る。
  # Ruby 側で選ぶ UserKarte#latest_finalized_questionnaire も同じ並びにすること。
  scope :latest_first, -> { order(Arel.sql("COALESCE(submitted_at, created_at) DESC, id DESC")) }

  # 患者が提出を完了し、確定した状態。draft 以外。
  #
  # submitted / reviewed を列挙するのではなく draft を除く形にしているのは、
  # 将来 status に値が増えたときに自動で含まれるようにするため。
  # 列挙にすると、追加した値が最新版の判定から静かに漏れる。
  #
  # confirmed ではなく finalized なのは、同じカルテ機能の中に
  # needs_confirmation? / confirmation_reasons（禁忌ではないが要確認）という
  # 無関係な概念があり、並ぶと互いの前提だと誤読されるため。
  # Reservation.confirmed（予約確定）とも別物。
  scope :finalized, -> { where.not(status: :draft) }

  def submit!(intake_session: nil)
    update!(status: :submitted, submitted_at: Time.current, intake_session: intake_session)
  end

  def answer(key) = answers[key.to_s]
end

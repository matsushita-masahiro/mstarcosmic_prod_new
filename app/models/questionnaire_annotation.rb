# 問診票へのスタッフ追記。
#
# 紙の問診票に赤ペンで書き添えていた運用の置き換え。設問ごとに1件ずつ足す。
#
# 【重要】患者の回答（medical_questionnaires.answers）には書かない。
# 問診票は previous_id で版を積む設計で、「患者が書いたものはその版のまま
# 残っている」という前提が訂正・差分・施術判断のすべてに効いている。
# 追記を answers に混ぜると、その前提が静かに崩れる。
#
# 患者には見せない。表示部品は app/views/karte/ の下にだけ置くこと。
# app/views/shared/ に置くと患者側（Intake::BaseController 配下）からも
# 参照できる位置に入る。
class QuestionnaireAnnotation < ApplicationRecord
  belongs_to :medical_questionnaire
  belongs_to :staff, class_name: "User"

  # 自由記述で何が書かれるか制御できないため暗号化する。
  # handwriting_entries.transcribed_text と同じ判断。
  #
  # treatment_notes.body も同種の情報だが平文のまま。稼働中のテーブルで
  # 既存データの移行が要るため、別途まとめて対応する方針。
  #
  # 非決定的（deterministic: true を付けない）。したがって
  # where(body: ...) では引けない。全文検索が要るようになったら、
  # そのとき決定的暗号化への移行を検討する。
  encrypts :body

  validates :body, presence: true
  validates :question_key, presence: true
  validate  :question_key_must_exist_in_form

  # 古い順。同じ設問に複数あるときは書かれた順に読ませる。
  scope :chronological, -> { order(:created_at, :id) }

  # 追加専用。書き間違いは訂正の追記を足す運用で、record を書き換えない。
  # update / destroy のルートも作っていない。
  #
  # persisted? で返すので、新規作成（save）は通り、保存済みレコードの
  # save / update だけが ActiveRecord::ReadOnlyRecord になる。
  def readonly? = persisted?

  private

  # 設問定義に無いキーを弾く。パラメータの改ざんや打ち間違いで、
  # どこにも表示されない追記が生まれるのを防ぐ。
  #
  # 引き当ては MedicalQuestionnaireForm.find（= collect_all）を使う。
  # 設問本体だけでなく detail / subs / other まで含むので、
  # カルテに出ている項目はすべて対象になる。
  #
  # 照合先は現行の設問定義1つだけ。form_version ごとの定義を持つ仕組みは
  # 無く、カルテの「すべての回答を見る」も現行の QUESTIONS を描いている
  # （app/views/karte/users/_questionnaire.html.erb）。
  # 画面に出ているものだけが追記できる、という対応になる。
  def question_key_must_exist_in_form
    return if question_key.blank? # presence 側に任せる
    return if MedicalQuestionnaireForm.find(question_key).present?

    errors.add(:question_key, "は現在の問診票の様式にありません")
  end
end

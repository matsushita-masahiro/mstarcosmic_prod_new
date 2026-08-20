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

  # 記入途中の内容を、患者端末の localStorage と同じ形で返す。
  #
  # intake のフォームはサーバの下書きを ERB では描かず、この JSON を
  # questionnaire_controller.js の復元処理にそのまま渡す。
  # 出所が localStorage でもサーバでも復元は1本のままにするため、
  # 形（キー名・値の型）を端末側に合わせている。
  # saveLocalDraft() の形を変えるときは、ここも一緒に変えること。
  #
  # PNG（image）は含めない。restore() は strokes からしか描き直さず、
  # 表示には要らない。HTML に base64 を埋めると本文が肥大するだけになる。
  #
  # savedAt は端末側と同じくミリ秒。24時間判定には使われない
  # （サーバの下書きは intake_session に紐づき、セッションは30分で失効する）。
  #
  # 戻せるものが何も無いときは nil を返す。空の下書きを渡すと
  # 画面は何も変わらないのに「読み込みました」とだけ出て患者を混乱させる。
  def draft_snapshot
    return nil unless persisted?

    handwriting = handwriting_snapshot
    marks = body_marks_snapshot
    return nil if answers.blank? && handwriting.empty? && marks.empty?

    {
      savedAt: (updated_at.to_f * 1000).round,
      answers: answers,
      handwriting: handwriting,
      bodyMarks: marks
    }
  end

  private

  # 端末側の collectHandwriting() と同じものだけを返す。
  #
  # collectHandwriting() は空欄のキーを落とすため、こちらが空欄を含めると
  # verifyRestore() が「保存されていたのに画面に戻っていない欄」と数え、
  # restoreVerified が false のまま partial 付きの送信が続いてしまう。
  # 「画面に戻せるか」で揃えるので、中身が空のものはここで落とす。
  def handwriting_snapshot
    handwriting_entries.each_with_object({}) do |entry, result|
      if entry.input_mode_keyboard?
        next if entry.transcribed_text.blank?
        result[entry.question_key] = { mode: "keyboard", text: entry.transcribed_text }
      else
        next if entry.strokes.blank?
        result[entry.question_key] = {
          mode: "pen", strokes: entry.strokes,
          width: entry.canvas_width, height: entry.canvas_height
        }
      end
    end
  end

  # 端末側の body-map は x / y を数値で持つ。
  # decimal のまま to_json すると文字列になり、送り返された値が
  # 端末側と一致しなくなるので float に揃える。
  def body_marks_snapshot
    body_marks.map do |mark|
      { side: mark.side, x: mark.x.to_f, y: mark.y.to_f,
        mark_type: mark.mark_type, note: mark.note }.compact
    end
  end
end

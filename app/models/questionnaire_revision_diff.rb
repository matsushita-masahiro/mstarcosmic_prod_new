# app/models/questionnaire_revision_diff.rb
#
# 訂正版と前版の差分。カルテ側の表示だけに使う。
#
# 【なぜ差分を保存せず毎回計算するか】
# 訂正版は前版を書き換えず、完全なレコードとして保存している
# （差分だけを持つと、記録漏れやバグで元の内容が戻せなくなるため）。
# 両方の版が揃っているので差分はいつでも作り直せる。
# 保存すると、本体と差分がずれたときにどちらが正しいか決められなくなる。
#
# 【フラグの一覧を書き写さないこと】
# 施術判断に関わるフラグは MedicalQuestionnaireFlags::WARNING_PREDICATES から
# 引く。設問が改訂されて条件が増えたとき、ここを書き写していると
# 増えたフラグの変化が静かに見逃される。
class QuestionnaireRevisionDiff
  Change = Struct.new(:key, :label, :before, :after, :known_question, keyword_init: true) do
    # 現在の様式に無い設問（前版の様式にしかない等）
    def unknown_question? = !known_question
  end

  BLANK_LABEL = "（未回答）".freeze

  def initialize(questionnaire)
    @questionnaire = questionnaire
    @previous = questionnaire&.previous_version
  end

  attr_reader :previous

  # 比べる相手がいるか（＝訂正版か）
  def present? = @previous.present?

  # 施術判断に関わるフラグが前版から変わったか。
  # 警告バナーを出すかどうかはこれで決める。
  def warning_flags_changed? = changed_warning_predicates.any?

  def changed_warning_predicates
    return [] unless present?

    MedicalQuestionnaireFlags::WARNING_PREDICATES.select do |predicate|
      @questionnaire.public_send(predicate) != @previous.public_send(predicate)
    end
  end

  # フラグの変化。「ペースメーカー装着: あり → なし」の形で出す。
  def flag_changes
    changed_warning_predicates.map do |predicate|
      Change.new(
        key: predicate,
        label: MedicalQuestionnaireFlags::REASONS[predicate],
        before: yes_no(@previous.public_send(predicate)),
        after: yes_no(@questionnaire.public_send(predicate)),
        known_question: true
      )
    end
  end

  # 設問の回答の変化。表示は必ず設問ラベルと選択肢ラベルで行い、
  # q10_pacemaker や "yes" のような生の値は出さない。
  def answer_changes
    return [] unless present?

    before = @previous.answers || {}
    after  = @questionnaire.answers || {}

    (before.keys | after.keys).sort.filter_map do |key|
      next if before[key] == after[key]

      question = MedicalQuestionnaireForm.find(key)
      Change.new(
        key: key,
        label: question ? question_label(question) : key,
        before: display_value(key, before[key]),
        after: display_value(key, after[key]),
        known_question: question.present?
      )
    end
  end

  # 手書きは内容の比較が難しいので、変わった欄の名前だけを出す。
  def handwriting_changes
    return [] unless present?

    before = @previous.handwriting_entries.index_by(&:question_key)
    after  = @questionnaire.handwriting_entries.index_by(&:question_key)

    (before.keys | after.keys).sort.filter_map do |key|
      next if same_handwriting?(before[key], after[key])

      question = MedicalQuestionnaireForm.find(key)
      Change.new(key: key, label: question ? question_label(question) : key,
                 before: nil, after: nil, known_question: question.present?)
    end
  end

  def body_marks_changed?
    return false unless present?

    normalized_marks(@questionnaire) != normalized_marks(@previous)
  end

  # 前版と様式が違うと、片方にしか無い設問がありうる。
  # そのときは差分の先頭で断り書きを出す。
  def form_version_changed?
    present? && @questionnaire.form_version != @previous.form_version
  end

  def any_change?
    flag_changes.any? || answer_changes.any? ||
      handwriting_changes.any? || body_marks_changed?
  end

  private

  def question_label(question)
    question[:no] ? "【#{question[:no]}】#{question[:label]}" : question[:label]
  end

  def display_value(key, value)
    return BLANK_LABEL if value.blank?

    Array(value).map { |v| MedicalQuestionnaireForm.label_for(key, v) }.join("、")
  end

  def yes_no(flag) = flag ? "あり" : "なし"

  def same_handwriting?(before, after)
    return true  if before.nil? && after.nil?
    return false if before.nil? || after.nil?

    before.input_mode == after.input_mode &&
      before.transcribed_text == after.transcribed_text &&
      before.strokes == after.strokes
  end

  # 座標は decimal。桁の揺れで「変更あり」にならないよう丸めてから比べる。
  def normalized_marks(questionnaire)
    questionnaire.body_marks.map do |mark|
      [ mark.side, mark.x.to_f.round(4), mark.y.to_f.round(4), mark.mark_type, mark.note.to_s ]
    end.sort
  end
end

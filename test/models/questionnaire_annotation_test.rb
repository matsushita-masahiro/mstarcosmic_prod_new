require "test_helper"

# 問診票へのスタッフ追記。
#
# 追加専用であること、設問定義に無いキーを受け付けないこと、
# 本文が暗号化されて保存されることを見る。
class QuestionnaireAnnotationTest < ActiveSupport::TestCase
  setup do
    @staff = create_user(email: "annot-staff@example.com", name: "山田スタッフ", user_type: "1")
    @patient = create_user(email: "annot-patient@example.com", name: "患者")
    @questionnaire = create_questionnaire
  end

  # ── 追加専用 ─────────────────────────────
  #
  # 書き間違いは訂正の追記を足す運用。update / destroy のルートも作っていないが、
  # コンソールや rake から触られても書き換わらないことをモデル側で押さえる。
  test "保存済みの追記は書き換えられない" do
    annotation = create_annotation(body: "電話で確認済み")

    assert_predicate annotation, :readonly?

    assert_raises(ActiveRecord::ReadOnlyRecord) do
      annotation.update!(body: "書き換え")
    end

    assert_equal "電話で確認済み", annotation.reload.body
  end

  # readonly? を persisted? で返しているので、新規作成は通ること。
  # true 固定にすると1件も作れなくなる。
  test "新規作成は通る" do
    annotation = QuestionnaireAnnotation.new(
      medical_questionnaire: @questionnaire, question_key: "q1_purpose",
      body: "補足", staff: @staff
    )

    assert_not_predicate annotation, :readonly?
    assert annotation.save, annotation.errors.full_messages.join(" / ")
  end

  # ── 設問キーの照合 ──────────────────────────
  test "設問定義に無いキーは弾く" do
    annotation = QuestionnaireAnnotation.new(
      medical_questionnaire: @questionnaire, question_key: "q99_nonexistent",
      body: "補足", staff: @staff
    )

    assert_not annotation.valid?
    assert_includes annotation.errors[:question_key], "は現在の問診票の様式にありません"
  end

  test "空のキーは弾く" do
    annotation = QuestionnaireAnnotation.new(
      medical_questionnaire: @questionnaire, question_key: "", body: "補足", staff: @staff
    )

    assert_not annotation.valid?
    assert_predicate annotation.errors[:question_key], :any?
  end

  # 設問本体だけでなく、付随項目・サブ項目・その他欄のキーも通ること。
  # MedicalQuestionnaireForm.find（collect_all 経由）で引いているので、
  # 取りこぼすとカルテに出ている項目に追記できなくなる。
  test "サブ項目やその他欄のキーも通る" do
    %w[q1_purpose q2_disease_name q6_other q8_per_day q13_pregnancy_weeks].each do |key|
      annotation = QuestionnaireAnnotation.new(
        medical_questionnaire: @questionnaire, question_key: key, body: "補足", staff: @staff
      )

      assert annotation.valid?, "#{key} が弾かれています: #{annotation.errors.full_messages}"
    end
  end

  test "本文が空なら弾く" do
    annotation = QuestionnaireAnnotation.new(
      medical_questionnaire: @questionnaire, question_key: "q1_purpose", body: "", staff: @staff
    )

    assert_not annotation.valid?
    assert_predicate annotation.errors[:body], :any?
  end

  # ── 暗号化 ──────────────────────────────
  #
  # 通院先や既往歴が入る前提の自由記述なので、平文で置かない。
  # handwriting_entries.transcribed_text と同じ扱い。
  test "本文は暗号化して保存される" do
    annotation = create_annotation(body: "A病院に通院中。担当は佐藤医師。")

    raw = ActiveRecord::Base.connection.select_value(
      "select body from questionnaire_annotations where id = #{annotation.id}"
    )

    assert_no_match(/A病院/, raw, "本文が平文で保存されています")
    assert_equal "A病院に通院中。担当は佐藤医師。", annotation.reload.body
  end

  # ── 並び順 ──────────────────────────────
  test "chronological は古い順" do
    old = create_annotation(body: "先に書いた", created_at: 2.days.ago)
    new = create_annotation(body: "あとで書いた", created_at: 1.hour.ago)

    assert_equal [ old.id, new.id ],
                 @questionnaire.questionnaire_annotations.chronological.map(&:id)
  end

  # ── 連鎖削除 ─────────────────────────────
  #
  # readonly? は destroy も止めるため、関連は dependent: :delete_all にしてある。
  # :destroy に戻すと、ここが ActiveRecord::ReadOnlyRecord で落ちる。
  test "問診票を消すと追記も消える" do
    annotation = create_annotation(body: "補足")

    @questionnaire.destroy

    assert_empty QuestionnaireAnnotation.where(id: annotation.id)
  end

  private

  def create_user(email:, name:, user_type: "2")
    User.create!(email: email, name: name, password: "password", user_type: user_type)
  end

  def create_questionnaire(**attrs)
    @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, status: :submitted,
      submitted_at: Time.current, answers: { "q1_purpose" => "肩こり" }, **attrs
    )
  end

  def create_annotation(body:, **attrs)
    QuestionnaireAnnotation.create!(
      medical_questionnaire: @questionnaire, question_key: "q1_purpose",
      body: body, staff: @staff, **attrs
    )
  end
end

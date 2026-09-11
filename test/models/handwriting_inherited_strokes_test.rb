require "test_helper"

# 手書きの新旧を分ける境界。
#
# 訂正では前版の strokes を復元してから書き足す。signature_pad の fromData が
# 復元ぶんを配列の先頭にそのまま連結するため、先頭N件が「元」になる。
# time（端末の時計）は使わない。
class HandwritingInheritedStrokesTest < ActiveSupport::TestCase
  # 実データと同じ形。signature_pad の toData() は
  # { penColor:, points: [{ x:, y:, time:, pressure: }] } の配列を返す。
  def group(seed)
    { "penColor" => "#111827", "dotSize" => 0, "minWidth" => 0.6, "maxWidth" => 2.2,
      "points" => [ { "x" => seed.to_f, "y" => seed.to_f,
                      "time" => 1_787_230_336_800 + seed, "pressure" => 0.5 } ] }
  end

  setup do
    @patient = User.create!(email: "hw@example.com", name: "患者", password: "password")
  end

  test "書き足した版では前版のストローク数が境界になる" do
    v1 = version(strokes: [ group(1), group(2) ])
    v2 = version(previous: v1, strokes: [ group(1), group(2), group(3) ])

    assert_equal({ "q1_purpose" => 2 }, v2.inherited_stroke_counts)
  end

  test "初回提出には境界が無い" do
    v1 = version(strokes: [ group(1) ])

    assert_empty v1.inherited_stroke_counts,
                 "境界が無ければ色分けのしようがない、という形を保つこと"
  end

  test "前の版に同じ欄が無ければ境界が無い" do
    v1 = version(strokes: [ group(1) ], key: "q1_purpose")
    v2 = version(previous: v1, strokes: [ group(7) ], key: "q3_history")

    assert_empty v2.inherited_stroke_counts
  end

  # 安全弁。患者が「消す」で全消ししてから書き直すと、先頭は前版と一致しない。
  # そのときは「全部が今回書かれたもの」に倒す。
  test "先頭が前版と一致しなければ境界は0になる" do
    v1 = version(strokes: [ group(1), group(2) ])
    v2 = version(previous: v1, strokes: [ group(9) ])

    assert_equal({ "q1_purpose" => 0 }, v2.inherited_stroke_counts,
                 "全消しして書き直した版が「全部が元」と判定されています")
  end

  test "前版と全く同じなら全部が元になる" do
    v1 = version(strokes: [ group(1), group(2) ])
    v2 = version(previous: v1, strokes: [ group(1), group(2) ])

    assert_equal({ "q1_purpose" => 2 }, v2.inherited_stroke_counts)
  end

  # 前版より短くなることは無い想定だが、短ければ引き継ぎはそこまで。
  test "前版より短くても境界が配列を越えない" do
    v1 = version(strokes: [ group(1), group(2), group(3) ])
    v2 = version(previous: v1, strokes: [ group(1) ])

    assert_equal({ "q1_purpose" => 1 }, v2.inherited_stroke_counts)
  end

  test "strokes が空の欄は境界を持たない" do
    v1 = version(strokes: [ group(1) ])
    v2 = version(previous: v1, strokes: [])

    assert_empty v2.inherited_stroke_counts
  end

  # 境界の算出に時刻を使っていないこと。time を入れ替えても結果が変わらない。
  test "time を入れ替えても境界は変わらない" do
    v1 = version(strokes: [ group(1), group(2) ])
    shuffled = [ group(1), group(2), group(3) ].map do |g|
      g.merge("points" => g["points"].map { |p| p.merge("time" => 1) })
    end
    v2 = version(previous: v1, strokes: shuffled)

    # 先頭が一致しなくなるので安全弁が働く＝時刻ではなく中身で見ている。
    assert_equal({ "q1_purpose" => 0 }, v2.inherited_stroke_counts,
                 "time の違いが中身の比較に含まれていません")
  end

  private

  def version(strokes:, previous: nil, key: "q1_purpose")
    questionnaire = @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, status: :submitted,
      submitted_at: Time.current, answers: {}, previous_version: previous
    )
    questionnaire.handwriting_entries.create!(
      question_key: key, input_mode: :pen, strokes: strokes,
      canvas_width: 353, canvas_height: 140
    )
    questionnaire
  end
end

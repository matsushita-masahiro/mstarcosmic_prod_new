require "test_helper"

class AnswerKeyRepairTest < ActiveSupport::TestCase
  test "壊れたキーを正しいキーに直し、値は変えない" do
    result = AnswerKeyRepair.repair(
      "q6_family_history][" => %w[糖尿病 癌],
      "q10_pacemaker" => "no"
    )

    assert_equal({ "q10_pacemaker" => "no", "q6_family_history" => %w[糖尿病 癌] },
                 result.answers)
    assert_equal [ { from: "q6_family_history][", to: "q6_family_history" } ], result.renames
    assert_empty result.conflicts
    assert result.safe_to_apply?
  end

  test "壊れたキーが無ければ何も変えない" do
    answers = { "q10_pacemaker" => "no", "q6_family_history" => %w[糖尿病] }
    result = AnswerKeyRepair.repair(answers)

    assert_equal answers, result.answers
    assert_not result.broken?
    assert_not result.safe_to_apply?
  end

  test "1レコードに複数の壊れたキーがあっても全部直す" do
    result = AnswerKeyRepair.repair(
      "q6_family_history][" => %w[糖尿病],
      "q15_items][" => %w[整体]
    )

    assert_equal({ "q6_family_history" => %w[糖尿病], "q15_items" => %w[整体] },
                 result.answers)
    assert_equal 2, result.renames.size
  end

  # コード修正後に上書き保存されると、正しいキーだけが残る。
  # 両方あるのは、片方が古い保存の残りという状態。
  test "正しいキーが既にあり値も同じなら、壊れたキーを落とすだけ" do
    result = AnswerKeyRepair.repair(
      "q6_family_history][" => %w[糖尿病],
      "q6_family_history" => %w[糖尿病]
    )

    assert_equal({ "q6_family_history" => %w[糖尿病] }, result.answers)
    assert_empty result.conflicts
    assert result.safe_to_apply?
  end

  # どちらが患者の回答か機械には決められない。人が中身を見て決める。
  test "正しいキーが既にあり値が違うなら、書き換えずに報告する" do
    result = AnswerKeyRepair.repair(
      "q6_family_history][" => %w[糖尿病],
      "q6_family_history" => %w[心臓病]
    )

    assert_equal 1, result.conflicts.size
    assert_empty result.renames
    assert result.broken?
    assert_not result.safe_to_apply?, "衝突があるレコードは自動で書き換えないこと"
  end

  test "answers が nil でも落ちない" do
    result = AnswerKeyRepair.repair(nil)

    assert_equal({}, result.answers)
    assert_not result.broken?
  end
end

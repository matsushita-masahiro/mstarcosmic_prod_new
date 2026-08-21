require "test_helper"

# 設問定義そのものの取り決め。
#
# ── なぜ定義にテストを置くのか ──────────────────────
#
# 性別（q0_gender）は長らく定義の外にあり、ビュー・JS・モデルの3か所に
# キーが直書きされていた。そこから症状が3つ同時に出ていた。
#
#   1. 訂正すると回答が消える   … 出力されないので collectAnswers() が拾えない
#   2. 署名の確認画面に出ない   … 回答一覧は QUESTIONS を走査している
#   3. 差分で「現在の様式にない設問」と出る … find() が nil を返す
#
# 根はどれも「定義に無い」の1つで、定義に入れれば同時に解決する。
# 逆に言うと、定義から外れた瞬間に3つとも戻るので、ここで固定しておく。
class MedicalQuestionnaireFormTest < ActiveSupport::TestCase
  test "性別が設問定義から引ける" do
    question = MedicalQuestionnaireForm.find(MedicalQuestionnaireForm::GENDER_KEY)

    assert question, "性別が定義にありません（差分で「現在の様式にない設問」と出ます）"
    assert_equal :radio, question[:type]
    assert_equal "性別", question[:label]
  end

  # 値を変えると users.gender への反映（sync_patient_gender!）と、
  # 既に保存されている過去の回答の両方が壊れる。
  test "性別の選択肢は users.gender への反映と対応している" do
    question = MedicalQuestionnaireForm.find(MedicalQuestionnaireForm::GENDER_KEY)

    assert_equal %w[female male], question[:options].map { |o| o[:value] },
                 "値を変えると sync_patient_gender! と過去の回答が食い違います"
  end

  test "性別は選択肢ラベルで表示できる" do
    key = MedicalQuestionnaireForm::GENDER_KEY

    assert_equal "女性", MedicalQuestionnaireForm.label_for(key, "female")
    assert_equal "男性", MedicalQuestionnaireForm.label_for(key, "male")
  end

  test "性別は冒頭で聞く" do
    assert_equal MedicalQuestionnaireForm::GENDER_KEY,
                 MedicalQuestionnaireForm::QUESTIONS.first[:key]
  end

  # 既存は【1】〜【19】。ぶつからない番号は 0 になるが、
  # 「【0】」と画面に出るのは不自然なので番号を持たせていない。
  test "性別は設問番号を持たない" do
    question = MedicalQuestionnaireForm.find(MedicalQuestionnaireForm::GENDER_KEY)

    assert_nil question[:no], "【0】と表示されます"
  end

  test "設問番号は重複しない" do
    numbers = MedicalQuestionnaireForm::QUESTIONS.filter_map { |q| q[:no] }

    assert_equal numbers.uniq, numbers
  end

  # female_only は「hidden で隠すだけ（DOM にはある）」、
  # ask_when_unknown は「そもそも出力しない」。性質が違う。
  # 両方を持つ設問ができると、隠すのか出さないのかが決まらず、
  # 訂正の持ち越し（Intake::QuestionnairesController#answers_to_save）が
  # 誤って前版の値を復活させうる。
  test "ask_when_unknown と female_only は同じ設問に付かない" do
    both = MedicalQuestionnaireForm::QUESTIONS.select do |q|
      q[:ask_when_unknown] && q[:female_only]
    end

    assert_empty both.map { |q| q[:key] },
                 "隠すのか出力しないのかが決まりません"
  end

  # 複数選択の「その他」欄（other）も定義から引けること。
  # 落とすと find が nil を返し、訂正の差分に
  # 「q6_other（現在の様式にない設問）」と出る。
  test "複数選択のその他欄も定義から引ける" do
    question = MedicalQuestionnaireForm.find("q6_other")

    assert question, "その他欄が定義から引けません"
    assert_equal "その他の難病指定されたもの", question[:label]
  end

  # 付随項目・サブ項目と同じ扱いになっていること。
  # collect_all から漏れるのは other だけだった。
  test "設問に連なる項目はすべて定義から引ける" do
    keys = MedicalQuestionnaireForm::QUESTIONS.flat_map do |q|
      [ q[:key], q.dig(:detail, :key), q.dig(:other, :key),
        *Array(q[:subs]).map { |sub| sub[:key] } ]
    end.compact

    missing = keys.reject { |key| MedicalQuestionnaireForm.find(key) }
    assert_empty missing, "定義から引けない項目があります"
  end

  test "ask_when_unknown を持つのは性別だけ" do
    keys = MedicalQuestionnaireForm::QUESTIONS
             .select { |q| q[:ask_when_unknown] }.map { |q| q[:key] }

    assert_equal [ MedicalQuestionnaireForm::GENDER_KEY ], keys
  end
end

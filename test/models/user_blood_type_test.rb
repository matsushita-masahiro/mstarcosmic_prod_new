require "test_helper"

# 血液型の述語と表示ラベル（UserKarte）。
#
# ── なぜ gender と別の意味論なのか ──────────────────────
#
# gender_known? は「認識できる値か」を見る。"unknown" のような値は偽になり、
# 問診票がもう一度性別を聞く。性別は必ずどちらかに決まるので、それでよい。
#
# 血液型は「分からない」が正当な答えになる。同じ意味論を採ると、
# 「不明」と答えた患者に来店のたびに同じことを聞き続けることになる。
# そこで blood_type_recorded? は「訊いたか」だけを見て、"unknown" も真にする。
# 名前を _known? にしていないのは、gender と対だと読めてしまうため。
class UserBloodTypeTest < ActiveSupport::TestCase
  # DB に触らない。判定も表示も保存済みかどうかと関係が無く、
  # User の検証に引きずられると値の組み合わせを作れなくなる。
  def build_user(blood_type)
    User.new(blood_type: blood_type)
  end

  # ── 訊いたかどうか ───────────────────────────
  test "回答があれば訊いたことになる" do
    %w[a b o ab].each do |value|
      assert_predicate build_user(value), :blood_type_recorded?,
                       "blood_type=#{value.inspect} が未回答扱いになっています"
    end
  end

  # この機能の核心。ここが偽になると、答えられない患者が来店のたびに
  # 同じ設問を出され続ける。
  test "不明と答えた患者も訊いたことになる" do
    assert_predicate build_user("unknown"), :blood_type_recorded?,
                     "「不明」と答えた患者に、次回また同じ設問が出ます"
  end

  test "未登録なら訊いていないことになる" do
    [ nil, "", "  " ].each do |value|
      assert_not build_user(value).blood_type_recorded?,
                 "blood_type=#{value.inspect} で設問が出なくなります"
    end
  end

  # ── 表示ラベル ────────────────────────────
  test "定義された値は日本語ラベルになる" do
    { "a" => "A型", "b" => "B型", "o" => "O型",
      "ab" => "AB型", "unknown" => "不明" }.each do |value, expected|
      assert_equal expected, build_user(value).blood_type_label,
                   "blood_type=#{value.inspect} が #{expected} になりません"
    end
  end

  test "未登録なら nil で、ヘッダーから項目ごと消える" do
    assert_nil build_user(nil).blood_type_label
  end

  # 生値を画面に出さないこと。users.gender の "f" がそのまま出ると
  # 患者に意味が通らないのと同じ理由。
  # 表記ゆれ吸収を置いていないので、大文字や Rh 付きも定義外になる。
  test "定義に無い値は nil で、生値を画面に出さない" do
    [ "A", "AB型", "a+", "rh-", "0", "不明", "その他", "" ].each do |value|
      label = build_user(value).blood_type_label

      assert_nil label, "blood_type=#{value.inspect} で #{label.inspect} が出ています"
    end
  end

  # 設問の選択肢とラベルの語彙が一致していること。
  # 片方だけ足すと、答えられるのに画面に出ない値ができる。
  test "設問の選択肢はすべてラベルを持つ" do
    values = MedicalQuestionnaireForm.find(MedicalQuestionnaireForm::BLOOD_TYPE_KEY)[:options]
                                     .map { |o| o[:value] }

    assert_equal values.sort, UserKarte::BLOOD_TYPE_LABELS.keys.sort,
                 "設問の選択肢と表示ラベルの語彙が食い違っています"
  end

  # 確認画面（設問定義側）とヘッダー（UserKarte 側）で呼び名が変わらないこと。
  # 同じ回答が画面によって別の名前で出ると、患者にもスタッフにも別物に見える。
  test "確認画面とヘッダーで同じ文言を使う" do
    key = MedicalQuestionnaireForm::BLOOD_TYPE_KEY

    UserKarte::BLOOD_TYPE_LABELS.each do |value, label|
      assert_equal label, MedicalQuestionnaireForm.label_for(key, value),
                   "#{value.inspect} の呼び名が画面によって違います"
    end
  end
end

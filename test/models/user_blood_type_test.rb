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

  # ── カルテ表示用ラベル ──────────────────────────
  #
  # 患者向けと分けているのは、未確定の2状態でスタッフの行動が変わるため。
  #   "unknown"    … 訊いたが患者が知らなかった → 聞き直しても得られない
  #   nil / 定義外 … まだ訊いていない          → 次回の問診票で埋まる
  test "カルテでは定義された値が日本語ラベルになる" do
    { "a" => "A型", "b" => "B型", "o" => "O型", "ab" => "AB型" }.each do |value, expected|
      assert_equal expected, build_user(value).karte_blood_type_label,
                   "blood_type=#{value.inspect} が #{expected} になりません"
    end
  end

  test "カルテでは不明と答えたことが分かる" do
    assert_equal "不明", build_user("unknown").karte_blood_type_label
  end

  test "カルテでは未登録も文言で出す" do
    [ nil, "", "  " ].each do |value|
      assert_equal "血液型未登録", build_user(value).karte_blood_type_label,
                   "blood_type=#{value.inspect} で未登録と分かりません"
    end
  end

  # 生値を画面に出さない。訊き直せば埋まる側に倒す。
  test "カルテでも定義に無い値は生値を出さず未登録に倒す" do
    [ "A", "AB型", "a+", "rh-", "0", "不明", "その他" ].each do |value|
      assert_equal "血液型未登録", build_user(value).karte_blood_type_label,
                   "blood_type=#{value.inspect} の生値が画面に出ています"
    end
  end

  # ここがこの機能の要。同じ文字列に畳むと区別そのものが消え、
  # スタッフには「聞き直せば分かるのか」が読めなくなる。
  test "訊いて不明だった患者と、まだ訊いていない患者は違う表示になる" do
    asked     = build_user("unknown").karte_blood_type_label
    not_asked = build_user(nil).karte_blood_type_label

    assert_not_equal asked, not_asked,
                     "「訊いたが不明」と「まだ訊いていない」が見分けられません"
    assert_equal "不明", asked
    assert_equal "血液型未登録", not_asked
  end

  # ── 患者向けの戻り値を変えていないこと ──────────────────
  #
  # カルテ用を足すついでに blood_type_label を「未登録」を返す形へ
  # 変えてしまうと、問診票ヘッダーの compact_blank が効かなくなり、
  # 患者の画面に内部状態が出る。落ちても例外にならないので明示的に見る。
  test "患者向けラベルは未登録でも nil を返し続ける" do
    [ nil, "", "  ", "a+", "その他" ].each do |value|
      assert_nil build_user(value).blood_type_label,
                 "blood_type=#{value.inspect} で患者向けの戻り値が変わっています"
    end
  end

  test "患者向けラベルは血液型未登録という文言を返さない" do
    labels = [ nil, "", "a+", "a", "unknown" ].map { |v| build_user(v).blood_type_label }

    assert_not_includes labels, "血液型未登録",
                        "カルテ用の文言が患者向けに漏れています"
  end

  # 定義された値では両者が一致していること。カルテ側だけ別の呼び名を
  # 持ち始めると、同じ患者が画面によって違う血液型に見える。
  test "登録済みならカルテと患者向けで同じ呼び名になる" do
    UserKarte::BLOOD_TYPE_LABELS.each_key do |value|
      user = build_user(value)

      assert_equal user.blood_type_label, user.karte_blood_type_label,
                   "#{value.inspect} の呼び名が画面によって違います"
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

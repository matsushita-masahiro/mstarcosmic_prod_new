require "test_helper"

# 患者向けヘッダー2行目の組み立て。
#
# 「出ないこと」だけを確かめても足りない。項目ごと消す仕様なので、
# 判定を間違えて全部消しても「消えている」テストは通ってしまう。
# 出るべきものが出ることと、出てはいけないものが出ないことを対で見る。
class Intake::PatientInfoHelperTest < ActionView::TestCase
  tests Intake::PatientInfoHelper

  # DB に触らない。ヘッダーの表示は保存済みかどうかと関係が無く、
  # User の検証（生年月日必須など）に引きずられると
  # 「生年月日が無い患者」の側が作れなくなる。
  def build_user(birthday: nil, gender: nil, blood_type: nil)
    User.new(birthday: birthday, gender: gender, blood_type: blood_type)
  end

  # ── 生年月日 ──────────────────────────────
  test "生年月日はゼロ埋めせずに年齢を添えて出す" do
    travel_to Date.new(2026, 8, 30) do
      assert_equal "1985年3月4日（41歳）",
                   patient_birthday_with_age(build_user(birthday: Date.new(1985, 3, 4)))
    end
  end

  test "生年月日が無ければ nil" do
    assert_nil patient_birthday_with_age(build_user(birthday: nil)),
               "「（歳）」だけが残ると壊れて見えます"
  end

  # 満年齢の境目。1日ずれると患者の年齢を1つ間違えて表示する。
  test "誕生日の前日はまだ歳を取らない" do
    travel_to Date.new(2026, 3, 3) do
      assert_match "40歳", patient_birthday_with_age(build_user(birthday: Date.new(1985, 3, 4)))
    end
  end

  test "誕生日当日に歳を取る" do
    travel_to Date.new(2026, 3, 4) do
      assert_match "41歳", patient_birthday_with_age(build_user(birthday: Date.new(1985, 3, 4)))
    end
  end

  test "誕生日の翌日も同じ歳" do
    travel_to Date.new(2026, 3, 5) do
      assert_match "41歳", patient_birthday_with_age(build_user(birthday: Date.new(1985, 3, 4)))
    end
  end

  # 2月29日生まれ。平年には誕生日そのものが無い。
  # 3月1日に歳を取る扱いで、2月28日時点ではまだ取らない。
  test "うるう日生まれは平年の2月28日ではまだ歳を取らない" do
    travel_to Date.new(2027, 2, 28) do
      assert_match "26歳", patient_birthday_with_age(build_user(birthday: Date.new(2000, 2, 29)))
    end
  end

  test "うるう日生まれは平年の3月1日に歳を取る" do
    travel_to Date.new(2027, 3, 1) do
      assert_match "27歳", patient_birthday_with_age(build_user(birthday: Date.new(2000, 2, 29)))
    end
  end

  # ── 性別 ────────────────────────────────
  # 実データは "f"(667) / "m"(196) / nil(46) / "男性"(1)。
  # 語彙は UserKarte が持っており、ここではその結果を患者向けに
  # 出し分けているだけであることを確かめる。
  test "判別できる値は日本語ラベルになる" do
    { "f" => "女性", "female" => "女性", "woman" => "女性", "女" => "女性",
      "女性" => "女性", "F" => "女性",
      "m" => "男性", "male" => "男性", "man" => "男性", "男" => "男性",
      "男性" => "男性", "M" => "男性" }.each do |value, expected|
      assert_equal expected, patient_gender_label(build_user(gender: value)),
                   "gender=#{value.inspect} が #{expected} になりません"
    end
  end

  test "判別できない値は nil で、未登録の文言を患者に見せない" do
    [ nil, "", "  ", "unknown", "その他", "0" ].each do |value|
      label = patient_gender_label(build_user(gender: value))

      assert_nil label, "gender=#{value.inspect} で #{label.inspect} が出ています"
    end
  end

  # gender_label 側の "未登録" をそのまま流していないこと。
  # スタッフには入力を促す文言だが、患者には意味が無い。
  test "未登録という文言は患者向けには出ない" do
    user = build_user(gender: nil)

    assert_equal "未登録", user.gender_label, "前提: カルテ側は未登録と出す"
    assert_nil patient_gender_label(user)
  end

  # ── 血液型 ───────────────────────────────
  #
  # 性別と違って patient_ 付きの包みを持たない。blood_type_label が
  # 未登録でも定義外でも nil を返すので、そのまま並べられる。
  # ここで確かめるのは、その nil がヘッダーで項目ごと消えること。
  test "血液型は日本語ラベルで並ぶ" do
    travel_to Date.new(2026, 8, 30) do
      user = build_user(birthday: Date.new(1985, 3, 4), gender: "f", blood_type: "a")

      assert_equal "生年月日：1985年3月4日（41歳） ／ 性別：女性 ／ 血液型：A型",
                   patient_attributes_line(user)
    end
  end

  # 「不明」は消さない。空欄にするとスタッフからは「まだ訊いていない」と
  # 見分けが付かず、もう一度訊くことになる。
  test "不明と答えた血液型も表示する" do
    travel_to Date.new(2026, 8, 30) do
      user = build_user(birthday: Date.new(1985, 3, 4), gender: "f", blood_type: "unknown")

      assert_equal "生年月日：1985年3月4日（41歳） ／ 性別：女性 ／ 血液型：不明",
                   patient_attributes_line(user)
    end
  end

  test "未登録の血液型は区切り記号ごと消える" do
    travel_to Date.new(2026, 8, 30) do
      user = build_user(birthday: Date.new(1985, 3, 4), gender: "f", blood_type: nil)

      assert_equal "生年月日：1985年3月4日（41歳） ／ 性別：女性",
                   patient_attributes_line(user)
    end
  end

  # 定義に無い値でも同じ。生値が「… ／ 性別：女性 ／ 血液型：a+」と
  # 並ぶより、項目ごと消えるほうがまだ読める。
  test "定義に無い血液型は生値を出さずに消える" do
    travel_to Date.new(2026, 8, 30) do
      user = build_user(birthday: Date.new(1985, 3, 4), gender: "f", blood_type: "a+")

      assert_equal "生年月日：1985年3月4日（41歳） ／ 性別：女性",
                   patient_attributes_line(user)
    end
  end

  test "血液型だけなら区切り記号を残さない" do
    assert_equal "血液型：O型",
                 patient_attributes_line(build_user(birthday: nil, gender: nil,
                                                    blood_type: "o"))
  end

  # ── 2行目全体 ─────────────────────────────
  test "両方あれば区切って並べる" do
    travel_to Date.new(2026, 8, 30) do
      user = build_user(birthday: Date.new(1985, 3, 4), gender: "f")

      assert_equal "生年月日：1985年3月4日（41歳） ／ 性別：女性",
                   patient_attributes_line(user)
    end
  end

  test "生年月日だけなら区切り記号を残さない" do
    travel_to Date.new(2026, 8, 30) do
      user = build_user(birthday: Date.new(1985, 3, 4), gender: nil)

      assert_equal "生年月日：1985年3月4日（41歳）", patient_attributes_line(user)
    end
  end

  test "性別だけなら区切り記号を残さない" do
    assert_equal "性別：女性", patient_attributes_line(build_user(birthday: nil, gender: "f"))
  end

  # 3項目すべて欠けたとき。1つでも判定を間違えると区切り記号だけが残る。
  test "3項目とも欠ければ空文字で、呼び出し側が行ごと落とせる" do
    line = patient_attributes_line(build_user(birthday: nil, gender: nil,
                                              blood_type: nil))

    assert_equal "", line
    assert_predicate line, :blank?
  end

  # 真ん中が欠けた形。区切り記号が二重（「／ ／」）にならないこと。
  test "真ん中が欠けても区切り記号は二重にならない" do
    travel_to Date.new(2026, 8, 30) do
      user = build_user(birthday: Date.new(1985, 3, 4), gender: nil, blood_type: "ab")

      assert_equal "生年月日：1985年3月4日（41歳） ／ 血液型：AB型",
                   patient_attributes_line(user)
    end
  end
end

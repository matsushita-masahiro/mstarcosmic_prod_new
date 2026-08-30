module Intake
  # 患者向けヘッダーの2行目（生年月日・年齢・性別）を組み立てる。
  #
  # 判定そのものはここに置かない。UserKarte が持っている
  # age / gender_known? / gender_label をそのまま呼ぶ。
  # 性別の表記ゆれ（"f" / "m" / nil / "男性"）を受ける語彙を
  # ここにもう一組定義すると、片方だけ直したときに
  # カルテと患者画面で判定が食い違う。語彙は UserKarte の1か所だけ。
  module PatientInfoHelper
    # 「1985年3月4日（41歳）」。生年月日が無ければ nil。
    # 生年月日が無いのに「（歳）」だけ残ると壊れて見えるので、
    # 項目ごと出さない。
    def patient_birthday_with_age(user)
      return nil if user.birthday.blank?

      "#{l(user.birthday, format: :birthday)}（#{user.age}歳）"
    end

    # 患者向けのラベル。判別できないときは nil。
    #
    # UserKarte#gender_label は未判別に "未登録" を返すが、それはスタッフが
    # 「入力が要る」と気づくための文言で、患者に見せるものではない。
    # 患者側では項目ごと消す。判別できない患者には問診票が q0_gender を
    # 聞くので、聞いている最中の情報をヘッダーで先に断定しないことにもなる。
    def patient_gender_label(user)
      return nil unless user.gender_known?

      user.gender_label
    end

    # 2行目そのもの。出せる項目が無ければ空文字を返し、
    # 呼び出し側が <p> ごと出さない。区切り記号だけが残らないよう
    # compact_blank してから繋ぐ。
    def patient_attributes_line(user)
      [ patient_birthday_with_age(user), patient_gender_label(user) ]
        .compact_blank
        .join(" ／ ")
    end
  end
end

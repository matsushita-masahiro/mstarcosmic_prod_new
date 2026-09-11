module Intake
  # 患者向けヘッダーの2行目（生年月日・年齢・性別・血液型）を組み立てる。
  #
  # 判定そのものはここに置かない。UserKarte が持っている
  # age / gender_known? / gender_label / blood_type_label をそのまま呼ぶ。
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

    # 2行目に出す項目。出せるものが無ければ空配列を返し、
    # 呼び出し側が <p> ごと出さない。
    #
    # ラベルは値と同じ要素に入れる。ラベルをここより外（ビューや
    # 書式文字列）に置くと、値が落ちた項目でラベルだけが残る。
    # filter_map で「値があるものだけラベル付きで返す」を1手で済ませている。
    #
    # 1項目ずつの配列で返し、並べ方はビューに任せる。" ／ " で繋いだ
    # 1本の文字列を返していた頃は、iPhone 幅で折り返すと行末に ／ が
    # ぶら下がり、血液型だけが次の行に落ちて読みにくかった。
    # 項目ごとに行を分ける組み方では区切り記号そのものが要らない。
    #
    # 血液型のラベルは省けない。生年月日と性別は値だけで何の項目か
    # 分かるが、「不明」は単独では読めない。
    #
    # 血液型に patient_ 付きの包みを作っていない。
    # 性別に patient_gender_label が要るのは gender_label が未判別に
    # "未登録" を返すからで、患者向けにそれを消す層が必要になる。
    # blood_type_label は未登録でも定義に無い値でも nil を返すため、
    # 包んでも同じものを返すことになる。名前だけが増える。
    #
    # 「不明」（患者が "unknown" と答えた）はここに出す。消すと
    # 訊いていない患者と見分けが付かず、もう一度訊くことになる。
    def patient_attributes(user)
      [ [ "生年月日", patient_birthday_with_age(user) ],
        [ "性別",     patient_gender_label(user) ],
        [ "血液型",   user.blood_type_label ] ]
        .filter_map { |label, value| "#{label}：#{value}" if value.present? }
    end
  end
end

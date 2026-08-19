require "test_helper"

# カルテ詳細の問診内容表示。
#
# ここは案件の中心機能で、「禁忌が出ない」「マーカーがずれる」は
# 患者の安全に直結する。表示が壊れても例外は出ず静かに間違うため、
# 落ちたときはテストの方を直さないこと。
#
# ── このファイルが守っているもの ──────────────────────
#
# 1. 座標変換（マーカーが記入時と同じ位置に出ること）
#    保存値 0.0〜1.0 → viewBox 0 0 100 100 の cx/cy へ x * 100 で写す。
#    記入側 body_map_controller.js と同じ式であることを固定する。
#
#    【重要・限界】このテストは「座標変換」を守るのであって
#    「描画位置」は守らない。人体図の形を描き直しても落ちない。
#    腕の位置がずれた図に差し替えれば、変換は正しいままマーカーは
#    別の部位に乗る。図の形が変わっていないことは 3 の viewBox 不変と
#    2 の共有パーシャル一本化で担保し、最終的な見た目は目視で確認すること。
#
# 2. 輪郭の一本化（記入側と表示側が同じ図を使っていること）
#    図が二重管理になると、片方だけ直して座標がずれる。
#    intake / karte の双方が shared/_body_outline をそのまま描いていることを見る。
#
# 3. viewBox の不変（0 0 100 100）
#    ここを変えると過去の全マーキングが別の部位に移る。
#    人体図 SVG を差し替えるときに最初に踏む地雷なので、明示的に固定する。
#
# 4. preload（表示クエリが手書き欄の数に比例しないこと）
#
# 5. 表示そのもの（要点・人体図・全設問・手書き画像）と
#    問診票が無い / 下書きのみの患者で落ちないこと
#
# 6. 提出履歴と展開状態
#    履歴は件数によらず常に全件出す（1件でも出す）。
#    全設問を開くかどうかは params[:questionnaire_id] の有無で決まる。
#    「最新かどうか」ではなく「明示的に選んだかどうか」が判定基準。
#
# 7. 未回答の出し分け
#    最上位の設問は答えていなければ出さない。
#    ただし show_when を満たして画面に出ていた項目は、空でも
#    「未選択 / 未記入」として出す（聞いたが答えなかった、と区別するため）。
#
# 8. 警告の根拠と既定の表示版（どちらも確定版に揃っていること）
#    ページ上部の赤／黄の警告は確定版だけを見る。履歴表は下書きも出すため、
#    両者の元ネタを取り違えると、書きかけの下書きが確定版を押しのけて
#    確定版の禁忌が画面から消える。
#    内容パネルの既定も同じ確定版に揃える。バナーと別の版が並ぶと、
#    「禁忌の項目が空」に見えてバナーの方が疑われる。
#
# 積み残しに「人体図 SVG の差し替え」がある。差し替え時は 1 の限界を踏まえ、
# 2 と 3 が通ることを確認したうえで、実際の見た目を必ず目視すること。
class KarteQuestionnaireTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # 1x1 の PNG（手書き画像の代わり）
  PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  )

  setup do
    # routes は遅延ロードのため、先に読ませないと Devise.mappings が空で sign_in が落ちる
    Rails.application.reload_routes_unless_loaded

    @staff = User.create!(email: "staff-karte-q@example.com", name: "スタッフ",
                          password: "password", user_type: "1")
    sign_in @staff
  end

  # ── 1. 座標変換 ────────────────────────────────
  #
  # 守るのは「保存値 → cx/cy の写し方」だけ。図の形は見ていない。
  # 詳しくはファイル冒頭の【重要・限界】を読むこと。
  test "マーカーが記入時と同じ座標に描かれる" do
    user = patient("marks")
    coords = [
      { side: "front", x: 0.27,  y: 0.45 },
      { side: "front", x: 0.5,   y: 0.45 },
      { side: "back",  x: 0.735, y: 0.62 },
      { side: "back",  x: 0.39,  y: 0.85 }
    ]
    make_questionnaire(user, marks: coords)

    get karte_user_path(user)
    assert_response :success

    circles = response.body.scan(/<circle\s+cx="([\d.]+)"\s+cy="([\d.]+)"/m)
                           .map { |cx, cy| [ cx.to_f, cy.to_f ] }
    expected = coords.map { |c| [ (c[:x] * 100).round(2), (c[:y] * 100).round(2) ] }

    assert_equal expected.sort, circles.sort,
                 "描画座標が記入時の x * 100 / y * 100 と一致しません"

    # 表・裏それぞれの図に振り分かること（両面が混ざると部位を取り違える）
    front_svg, back_svg = response.body.scan(/<svg[^>]*viewBox="0 0 100 100".*?<\/svg>/m)
    assert_equal 2, front_svg.scan(/<circle/).size, "表のマーカーは2件"
    assert_equal 2, back_svg.scan(/<circle/).size,  "裏のマーカーは2件"
  end

  # ── 2. 輪郭の一本化 ────────────────────────────
  #
  # 記入側・表示側の双方が shared/_body_outline をそのまま描いていること。
  # どちらかが自前の図を持ち始めると、片方だけ直して座標がずれる。
  test "記入側と表示側が同じ輪郭パーシャルを描いている" do
    user = patient("outline")
    make_questionnaire(user, marks: [ { side: "front", x: 0.5, y: 0.5 } ])

    shared = path_data(ApplicationController.render(partial: "shared/body_outline"))
    assert_operator shared.size, :>, 0, "共有パーシャルに path がありません"

    get karte_user_path(user)
    karte = path_data(response.body)

    intake = path_data(
      ApplicationController.render(
        partial: "intake/questionnaires/body_figure", locals: { side: "front" }
      )
    )

    assert_equal shared, intake, "記入側の輪郭が共有パーシャルと違います"
    assert_equal shared, karte & shared, "表示側の輪郭が共有パーシャルと違います"
    assert_equal shared.size * 2, karte.size, "表示側は表・裏の2枚ぶん描くこと"
  end

  # ── 3. viewBox の不変 ──────────────────────────
  #
  # 0 0 100 100 は保存済みマーキングの座標系そのもの。
  # ここを変えると過去のマーカーが全部ずれる。図を差し替えても変えないこと。
  test "記入側と表示側の viewBox が 0 0 100 100 で揃っている" do
    user = patient("viewbox")
    make_questionnaire(user, marks: [ { side: "front", x: 0.5, y: 0.5 } ])

    intake = ApplicationController.render(
      partial: "intake/questionnaires/body_figure", locals: { side: "front" }
    )
    assert_match(/<svg[^>]*viewBox="0 0 100 100"/, intake,
                 "記入側の viewBox が変わっています（過去のマーキングがずれます）")

    get karte_user_path(user)
    assert_equal 2, response.body.scan(/viewBox="0 0 100 100"/).size,
                 "表示側の viewBox が変わっています（過去のマーキングがずれます）"
  end

  # ── 4. preload ────────────────────────────────
  test "手書き欄が増えても表示クエリが比例しない" do
    few = patient("few")
    make_questionnaire(few, pen_keys: %w[q1_purpose],
                       marks: [ { side: "front", x: 0.2, y: 0.2 } ])

    many = patient("many")
    make_questionnaire(many,
      pen_keys: %w[q1_purpose q3_history q5_occupation q16_concerns
                   q17_removed_organ q17_anticancer q17_radiation
                   q17_advanced q17_exosome q17_other],
      marks: (1..10).map { |i| { side: "front", x: i / 20.0, y: i / 20.0 } })

    small = count_queries { get karte_user_path(few) }
    assert_response :success
    large = count_queries { get karte_user_path(many) }
    assert_response :success

    assert_operator (large - small), :<=, 3,
                    "手書き欄を1→10に増やしてクエリが #{large - small} 本増えています" \
                    "（handwriting_entries / body_marks の preload が効いていない）"
  end

  # ── 5. 表示 ───────────────────────────────────
  test "要点・人体図・全設問・手書き画像が出る" do
    user = patient("full")
    make_questionnaire(user,
      answers: {
        "q2_under_treatment" => "yes", "q4_medication" => "yes",
        "q10_pacemaker" => "no", "q17_has_additional" => "yes"
      },
      pen_keys: %w[q1_purpose q17_removed_organ],
      keyboard: { "q16_concerns" => "肩が重い感じが続いています" },
      marks: [ { side: "front", x: 0.27, y: 0.45, mark_type: "pain", note: "ここが痛い" } ])

    get karte_user_path(user)
    assert_response :success
    body = response.body

    # 要点（主訴・治療中・服薬・悩み）
    assert_match MedicalQuestionnaireForm.find("q1_purpose")[:label], body
    assert_match "肩が重い感じが続いています", body

    # 全設問は折りたたみ
    assert_match "すべての回答を見る", body
    assert_match "<details", body

    # 人体図とマーカーのメモ
    assert_match "痛み・気になるところ", body
    assert_match "ここが痛い", body

    # 手書き画像はタップで原寸が開く
    assert_match(/<a [^>]*target="_blank"[^>]*>\s*<img/m, body)

    # サブ項目も入れ子で出る
    assert_match "摘出臓器", body
  end

  # ── 7. 未回答の出し分け ────────────────────────
  #
  # 最上位の設問は、答えていなければ出さない（18問すべてを毎回読む運用ではなく、
  # 「いいえ」と「未記入」が並ぶと目が滑るため）。
  #
  # ただし show_when を満たして画面に出ていた項目だけは例外で、
  # 空でも「未選択 / 未記入」として出す。
  # 【19】感染したか「はい」→ 回数を選ばず送信、を黙って隠すと
  # 「感染していないから聞かれていない」のか「聞いたが答えなかった」のか
  # 区別できず、問診票として意味が変わる。回数は必須にしていないので
  # この状態は実際に起きる（本番で発生済み）。
  test "最上位の未回答の設問は表示しない" do
    user = patient("sparse")
    make_questionnaire(user, answers: { "q10_pacemaker" => "no" })

    get karte_user_path(user)
    assert_response :success

    assert_match MedicalQuestionnaireForm.find("q10_pacemaker")[:label], response.body
    # 回答していない最上位の設問のラベルは出さない（show_when を持たない）
    assert_no_match(/#{Regexp.escape(MedicalQuestionnaireForm.find('q5_occupation')[:label])}/,
                    response.body)
    assert_equal 0, unanswered_markers.size, "未回答の印を出さないこと"
  end

  test "条件を満たすのに空の項目は「未選択」として出す" do
    user = patient("unanswered-select")
    # 【19】はい → 感染回数を選ばずに送信（キーごと無い場合と空文字の両方）
    make_questionnaire(user, answers: { "q19_infected" => "yes" })

    get karte_user_path(user)
    assert_response :success

    assert_match "感染回数", response.body, "条件を満たしていれば行を出すこと"
    assert_match "未選択", response.body

    blank = patient("blank-select")
    make_questionnaire(blank, answers: { "q19_infected" => "yes",
                                         "q19_infection_count" => "" })
    get karte_user_path(blank)
    assert_match "感染回数", response.body, "空文字でも行を出すこと"
    assert_match "未選択", response.body
  end

  test "条件を満たさない項目は出さない" do
    user = patient("not-asked")
    make_questionnaire(user, answers: { "q19_infected" => "no" })

    get karte_user_path(user)
    assert_response :success

    assert_match MedicalQuestionnaireForm.find("q19_infected")[:label], response.body
    assert_no_match(/感染回数/, response.body, "聞かれていない項目は出さないこと")
    assert_equal 0, unanswered_markers.size
  end

  test "値が入っていれば従来どおり値を出す" do
    user = patient("answered-select")
    make_questionnaire(user, answers: { "q19_infected" => "yes",
                                        "q19_infection_count" => "2" })

    get karte_user_path(user)
    assert_response :success

    assert_match "感染回数", response.body
    assert_match "2回", response.body
    assert_equal 0, unanswered_markers.size, "値があるなら未回答の印は出さないこと"
  end

  test "【18】も【19】と同じ出し分けになる" do
    asked = patient("q18-asked")
    make_questionnaire(asked, answers: { "q18_vaccinated" => "yes" })
    get karte_user_path(asked)
    assert_match "接種回数", response.body
    assert_match "未選択", response.body

    not_asked = patient("q18-not-asked")
    make_questionnaire(not_asked, answers: { "q18_vaccinated" => "no" })
    get karte_user_path(not_asked)
    assert_no_match(/接種回数/, response.body)
  end

  # 要点ブロックの4項目（q1/q2/q4/q16）自体は show_when を持たないので従来どおりだが、
  # 【2】治療中・【4】服薬 は show_when 付きの detail（病名・薬名）を連れている。
  # そのため要点ブロックにも「病名 未記入」が出るようになる。
  # 治療中と答えながら病名が空、は臨床的に意味があるのでこの挙動を採る。
  # 要点をあくまで4行に保ちたくなったら、ここを見て意図的に変えること。
  test "要点ブロックでも条件を満たす詳細は未記入として出る" do
    user = patient("summary-detail")
    make_questionnaire(user, answers: { "q2_under_treatment" => "yes",
                                        "q4_medication" => "yes" })

    get karte_user_path(user)
    assert_response :success

    summary = summary_block
    assert_match "病名", summary
    assert_match "薬名", summary
    assert_equal %w[未記入 未記入],
                 summary.scan(%r{<span style="color:#9ca3af;">(未選択|未記入)</span>}).flatten
  end

  # 「いいえ」なら detail は聞かれていないので、要点は従来どおり4行のまま
  test "要点ブロックは条件を満たさない詳細を出さない" do
    user = patient("summary-plain")
    make_questionnaire(user, answers: { "q2_under_treatment" => "no",
                                        "q4_medication" => "no" })

    get karte_user_path(user)
    assert_response :success

    summary = summary_block
    assert_no_match(/病名/, summary)
    assert_no_match(/薬名/, summary)
    assert_equal 0, summary.scan(%r{<span style="color:#9ca3af;">(未選択|未記入)</span>}).size
  end

  # 手書きは「未記入」。【17】のサブ項目は全て手書き。
  test "条件を満たすのに手書きが無い項目は「未記入」として出す" do
    user = patient("no-handwriting")
    make_questionnaire(user, answers: { "q17_has_additional" => "yes" },
                       pen_keys: %w[q17_removed_organ])

    get karte_user_path(user)
    assert_response :success

    # 書いたものは画像で出る
    assert_match "摘出臓器", response.body
    # 書かなかったサブ項目は未記入として出る
    assert_match "抗がん剤", response.body
    assert_match "未記入", response.body
  end

  test "複数回提出があると日付で切り替えられる" do
    user = patient("multi")
    old = make_questionnaire(user, keyboard: { "q16_concerns" => "古い方の記載" },
                             submitted_at: 3.months.ago)
    recent = make_questionnaire(user, keyboard: { "q16_concerns" => "新しい方の記載" },
                                submitted_at: 1.day.ago)

    # 既定は最新
    get karte_user_path(user)
    assert_match "新しい方の記載", response.body
    assert_no_match(/古い方の記載/, response.body)

    # どちらを選んでいても履歴には全件並ぶ（選択中は「表示中」）
    assert_match(/questionnaire_id=#{recent.id}/, response.body)
    assert_match(/questionnaire_id=#{old.id}/, response.body, "選択中でない回も履歴に出ること")
    assert_match "表示中", response.body
    assert_match "この回を見る", response.body

    # 明示指定で切り替わる
    get karte_user_path(user, questionnaire_id: old.id)
    assert_match "古い方の記載", response.body
    assert_no_match(/新しい方の記載/, response.body)
    assert_match(/questionnaire_id=#{recent.id}/, response.body, "切り替え後も全件並ぶこと")
  end

  # ── 6. 提出履歴と展開状態 ──────────────────────
  #
  # 履歴は件数によらず常に出す。以前は2件以上のときだけ日付ボタンを出していたため、
  # 1件の患者では「いつ提出されたものか」が分かりにくかった。
  # 「2件以上のときだけ」に戻す変更を弾くため、1件の場合を明示的に固定する。
  test "問診票が1件でも提出履歴の一覧が出る" do
    user = patient("single")
    questionnaire = make_questionnaire(user, keyboard: { "q16_concerns" => "1件目の記載" })

    get karte_user_path(user)
    assert_response :success

    assert_match(/questionnaire_id=#{questionnaire.id}/, response.body,
                 "1件でも履歴の行が出ること")
    assert_match "表示中", response.body
    assert_match "様式 #{questionnaire.form_version}", response.body
  end

  # 履歴から選んだ回は全設問を開いて出す。
  # 過去の回をわざわざ開くのは中身を読みたいときなので、毎回たたむのは手数が増える。
  # 逆に最新は要点だけ見る運用が多いため折りたたむ。
  test "履歴から選んだときは全設問が開き、最新をそのまま開いたときは折りたたむ" do
    user = patient("expand")
    old = make_questionnaire(user, keyboard: { "q16_concerns" => "古い方" },
                             submitted_at: 3.months.ago)
    make_questionnaire(user, keyboard: { "q16_concerns" => "新しい方" },
                       submitted_at: 1.day.ago)

    get karte_user_path(user)
    assert_response :success
    assert_not details_open?, "最新をそのまま開いたときは折りたたむこと"

    get karte_user_path(user, questionnaire_id: old.id)
    assert_response :success
    assert details_open?, "履歴から選んだときは全設問を開くこと"
  end

  # 判定は「最新かどうか」ではなく「明示的に選んだかどうか」
  test "最新でも明示的に選べば全設問が開く" do
    user = patient("explicit")
    questionnaire = make_questionnaire(user, keyboard: { "q16_concerns" => "本文" })

    get karte_user_path(user, questionnaire_id: questionnaire.id)

    assert_response :success
    assert details_open?, "明示指定なら最新でも開くこと"
  end

  # expanded を渡さない呼び出しは折りたたみ側に倒す。
  #
  # show.html.erb は必ず expanded を渡すので、既定値はページ経由では確かめられない。
  # 「渡さなくても壊れない」は _questionnaire の対外的な約束なので、
  # パーシャルを直接描いて固定する。
  test "expanded を渡さずに描くと折りたたまれる" do
    user = patient("default-expanded")
    questionnaire = make_questionnaire(user, keyboard: { "q16_concerns" => "本文" })

    html = ApplicationController.render(
      partial: "karte/users/questionnaire", locals: { questionnaire: questionnaire }
    )

    tag = html[/<details[^>]*>/m]
    assert tag, "全設問の折りたたみが見つかりません"
    assert_not tag.include?("open"), "expanded 未指定のときは折りたたむこと"
  end

  test "履歴が増えても表示クエリが比例しない" do
    few = patient("hist-few")
    make_questionnaire(few, keyboard: { "q16_concerns" => "1件目" })

    many = patient("hist-many")
    8.times do |i|
      make_questionnaire(many, keyboard: { "q16_concerns" => "#{i}件目" },
                         submitted_at: i.days.ago)
    end

    small = count_queries { get karte_user_path(few) }
    assert_response :success
    large = count_queries { get karte_user_path(many) }
    assert_response :success

    assert_operator (large - small), :<=, 3,
                    "履歴を1→8件に増やしてクエリが #{large - small} 本増えています"
  end

  # 読み込み済みの @questionnaires からしか選ばないため、他人の ID は拾えない
  test "他人の問診票 ID を渡しても表示されない" do
    mine  = patient("mine")
    other = patient("other")
    make_questionnaire(mine,  keyboard: { "q16_concerns" => "自分の記載" })
    theirs = make_questionnaire(other, keyboard: { "q16_concerns" => "他人の記載" })

    get karte_user_path(mine, questionnaire_id: theirs.id)
    assert_response :success
    assert_match "自分の記載", response.body
    assert_no_match(/他人の記載/, response.body)
  end

  test "問診票が無い患者でも下書きだけの患者でも落ちない" do
    empty = patient("empty")
    get karte_user_path(empty)
    assert_response :success
    assert_match "まだ問診票がありません。", response.body

    draft = patient("draft")
    MedicalQuestionnaire.create!(user: draft, answers: {},
                                 form_version: MedicalQuestionnaireForm::VERSION)
    get karte_user_path(draft)
    assert_response :success
    assert_match "下書き", response.body
  end

  # ── 8. 警告の根拠 ─────────────────────────────
  #
  # ページ上部の警告（show.html.erb の「施術できません」／「確認してください」）は
  # 確定版だけを根拠にする。履歴表と同じ @questionnaires.first を使うと、
  # 患者が書きかけて離脱した下書きが最新版になり、次の2つが起きる。
  #
  #   ・下書きで何もチェックしていない → 確定版の禁忌が押しのけられて消える（危険）
  #   ・下書きでチェックした直後に離脱   → 確定版に無い禁忌が出る（過剰）
  #
  # 前者があるため「下書きを含めるのは安全側」ではない。
  # なお履歴表の各行は各版の状態をそのまま出す（そちらは下書きも禁忌も出してよい）。
  test "確定版の禁忌は、あとから空の下書きが作られても消えない" do
    user = patient("draft-hides-warning")
    make_questionnaire(user, answers: { "q10_pacemaker" => "yes" },
                       submitted_at: 3.days.ago)

    get karte_user_path(user)
    assert_match "施術できません", response.body, "前提: 確定版だけなら警告が出ること"

    # 患者が書きかけて離脱した状態。空なので禁忌のフラグは何も立たない。
    draft = MedicalQuestionnaire.create!(user: user, answers: {},
                                         form_version: MedicalQuestionnaireForm::VERSION)
    assert draft.status_draft?

    get karte_user_path(user)
    assert_response :success
    assert_match "施術できません", response.body,
                 "空の下書きが確定版を押しのけ、確定版の禁忌が消えています"
    assert_match "ペースメーカー装着", response.body
  end

  test "下書きしか無ければ、その下書きの禁忌では警告を出さない" do
    user = patient("draft-only-warning")
    draft = MedicalQuestionnaire.create!(user: user,
                                         answers: { "q10_pacemaker" => "yes" },
                                         form_version: MedicalQuestionnaireForm::VERSION)
    assert draft.status_draft?
    assert draft.contraindicated?, "前提: 下書き自体は禁忌の状態であること"

    get karte_user_path(user)
    assert_response :success
    assert_no_match(/施術できません/, response.body,
                    "未提出の下書きを根拠に施術不可を出さないこと")
    assert_no_match(/確認してください/, response.body)
  end

  test "警告の根拠が変わっても履歴表には下書き行が出る" do
    user = patient("draft-row-kept")
    submitted = make_questionnaire(user, answers: { "q10_pacemaker" => "yes" },
                                   submitted_at: 3.days.ago)
    draft = MedicalQuestionnaire.create!(user: user, answers: {},
                                         form_version: MedicalQuestionnaireForm::VERSION)

    get karte_user_path(user)
    assert_response :success

    assert_match(/questionnaire_id=#{draft.id}/, response.body, "履歴に下書き行が出ること")
    assert_match(/questionnaire_id=#{submitted.id}/, response.body)
    assert_match "下書き", response.body
    # 履歴表の各行は各版の状態をそのまま出す（上部の警告とは別物）
    assert_match "⚠ ペースメーカー装着", response.body
  end

  # 既定の表示版。バナーと内容パネルは同じ版を指す。
  #
  # 施術直前に画面を見る人はバナーで警戒してから内容を確認する。
  # そこで該当項目が空だと、疑われるのは下書きではなくバナーの方になる。
  # 警告の信頼性が落ちるのが最も避けたい結果なので、既定は確定版に揃える。
  test "最新が下書きでも、内容パネルは確定版を表示する" do
    user = patient("default-finalized")
    submitted = make_questionnaire(user,
      answers: { "q10_pacemaker" => "yes" },
      keyboard: { "q16_concerns" => "確定版の記載" },
      submitted_at: 3.days.ago)
    draft = MedicalQuestionnaire.create!(user: user,
      answers: {}, form_version: MedicalQuestionnaireForm::VERSION)
    draft.handwriting_entries.create!(question_key: "q16_concerns",
                                      input_mode: :keyboard,
                                      transcribed_text: "書きかけの記載")

    get karte_user_path(user)
    assert_response :success

    assert_match "施術できません", response.body
    assert_match "確定版の記載", response.body,
                 "バナーが確定版の禁忌を出しているのに、内容パネルが下書きを出しています"
    assert_no_match(/書きかけの記載/, response.body)

    # 履歴表では確定版の行が選択中になっている
    assert_match(/questionnaire_id=#{draft.id}/, response.body, "下書き行は履歴に残ること")
    assert_match(/questionnaire_id=#{submitted.id}/, response.body)
  end

  # 既定を変えただけで、明示指定の経路は従来どおり
  test "履歴から下書きを選べば下書きが表示される" do
    user = patient("explicit-draft")
    make_questionnaire(user, keyboard: { "q16_concerns" => "確定版の記載" },
                       submitted_at: 3.days.ago)
    draft = MedicalQuestionnaire.create!(user: user,
      answers: {}, form_version: MedicalQuestionnaireForm::VERSION)
    draft.handwriting_entries.create!(question_key: "q16_concerns",
                                      input_mode: :keyboard,
                                      transcribed_text: "書きかけの記載")

    get karte_user_path(user, questionnaire_id: draft.id)
    assert_response :success

    assert_match "書きかけの記載", response.body, "明示指定なら下書きも見られること"
    assert_no_match(/確定版の記載/, response.body)
  end

  # 確定版が1件も無いときのフォールバック。
  # 内容は出すが警告は出さない（下書きの禁忌では警告を出さないと決めたため）。
  test "確定版が無ければ下書きを表示し、警告は出さない" do
    user = patient("draft-fallback")
    draft = MedicalQuestionnaire.create!(user: user,
      answers: { "q10_pacemaker" => "yes" },
      form_version: MedicalQuestionnaireForm::VERSION)
    draft.handwriting_entries.create!(question_key: "q16_concerns",
                                      input_mode: :keyboard,
                                      transcribed_text: "書きかけの記載")
    assert draft.contraindicated?, "前提: 下書き自体は禁忌の状態であること"

    get karte_user_path(user)
    assert_response :success

    assert_match "書きかけの記載", response.body,
                 "確定版が無いなら、何も出さずに下書きを見せること"
    assert_no_match(/施術できません/, response.body)
    assert_no_match(/確認してください/, response.body)
  end

  private

  def patient(suffix)
    User.create!(email: "patient-#{suffix}@example.com", name: "患者#{suffix}",
                 password: "password")
  end

  def make_questionnaire(user, answers: {}, marks: [], pen_keys: [], keyboard: {},
                         submitted_at: Time.current)
    questionnaire = MedicalQuestionnaire.new(
      user: user, answers: answers, form_version: MedicalQuestionnaireForm::VERSION
    )
    questionnaire.status = :submitted
    questionnaire.submitted_at = submitted_at
    questionnaire.save!

    pen_keys.each do |key|
      entry = questionnaire.handwriting_entries.create!(
        question_key: key, input_mode: :pen, strokes: [ [ { "x" => 1, "y" => 1 } ] ]
      )
      entry.image.attach(io: StringIO.new(PNG), filename: "#{key}.png",
                         content_type: "image/png")
    end

    keyboard.each do |key, text|
      questionnaire.handwriting_entries.create!(
        question_key: key, input_mode: :keyboard, transcribed_text: text
      )
    end

    marks.each do |mark|
      questionnaire.body_marks.create!(
        side: mark[:side], x: mark[:x], y: mark[:y],
        mark_type: mark[:mark_type] || "pain", note: mark[:note]
      )
    end

    questionnaire
  end

  def path_data(html)
    html.scan(/<path d="([^"]+)"/).flatten
  end

  # 要点ブロック（全設問の details より前）だけを切り出す
  def summary_block
    body = response.body
    start = body.index("background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;")
    finish = body.index("<details")
    raise "要点ブロックが見つかりません" if start.nil? || finish.nil?

    body[start...finish]
  end

  # 「未選択 / 未記入」の印。ページ末尾の注記（※ 未記入の項目は…）と混ざらないよう、
  # パーシャルが出す span の形で数える。
  def unanswered_markers
    response.body.scan(%r{<span style="color:#9ca3af;">(未選択|未記入)</span>}).flatten
  end

  # 全設問の details が開いた状態か。
  # 展開の既定値を変える／expanded を渡し忘れる、のどちらでも落ちるようにここで見る。
  def details_open?
    tag = response.body[/<details[^>]*>/m]
    raise "details が見つかりません（全設問の折りたたみが消えています）" if tag.nil?

    tag.include?("open")
  end

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if payload[:name].to_s =~ /SCHEMA|TRANSACTION/
      count += 1
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end

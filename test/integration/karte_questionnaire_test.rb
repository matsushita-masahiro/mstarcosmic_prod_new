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

  test "未記入の設問は表示しない" do
    user = patient("sparse")
    make_questionnaire(user, answers: { "q10_pacemaker" => "no" })

    get karte_user_path(user)
    assert_response :success

    assert_match MedicalQuestionnaireForm.find("q10_pacemaker")[:label], response.body
    # 回答していない設問のラベルは出さない
    assert_no_match(/#{Regexp.escape(MedicalQuestionnaireForm.find('q5_occupation')[:label])}/,
                    response.body)
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

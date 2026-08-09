require "application_system_test_case"

# カルテ詳細（/karte/users/:id）の「問診票」提出履歴テーブルの列幅。
#
# ── なぜ実ブラウザで測るのか ────────────────────────
#
# reserves.scss に、セレクタが素のままの
#   thead, tbody tr { display: table; width: 100%; table-layout: fixed }
# がある。予約カレンダーのスクロール実装がこれに依存しているため
# あちらは触れず、結果として全アプリの表がこの指定を受ける。
# ビューで <tbody> を書いていなくても HTML パーサが自動挿入するので、
# CSS はソースではなく DOM を見て当たる。
#
# この環境では各 <tr> が独立した table ボックスになり、列幅は fixed で
# 決まる。日付セルに width:1% を置くと 1% × 900px = 9px に化け、
# white-space:nowrap の日付が隣の「様式」セルへ 148px あふれて重なる。
# 本番では form_version が "2026-04-17" 形式なので、隣に出る
# 「様式 2026-04-17」と日付が重なり、日付が二重に見える。
#
# 例外は出ず HTML も正しいため、リクエストテストでは検知できない。
# 計算後のセル座標を実ブラウザで測るしかない。
#
# ── このテストが2度目の再発を受けて書かれた経緯 ──────────
#
# 同じ修正が2回失われている。
#   bc9cf9c  width:1% を外し table-layout:auto で打ち消す（行ごとに幅がばらつく）
#   d181354  打ち消しをやめ日付セルに width:14em を置く（正しい修正）
#   666b6d1  d181354 より前の版をベースに show.html.erb を上書き → width:1% に戻る
#
# 2回とも目視でしか気づけず、レビューもすり抜けた。以下で座標を固定する。
#
# ── 落ちたときに疑うところ ──────────────────────────
#
#   「列が fixed で組まれている」が落ちた → CSS 未ビルド。yarn build:css を先に。
#     bin/rails test は CSS を作り直さないため、SCSS を変えた直後は古い
#     app/assets/builds/application.css で走る。
#   それ以外が落ちた → show.html.erb の日付セルの width を確認する。
#     幅を変える正当な理由があるならこのテストの期待値も更新すること。
#     テストを消して通すのは、3度目を仕込むのと同じ。
class Karte::QuestionnaireHistoryTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  # 日付セルに与えている幅。show.html.erb と揃えること。
  DATE_CELL_EM = 14

  # 隣のセルとの間にこれだけは空いていてほしい、という最低限の余白。
  # 0 でも「重なっていない」ことは言えるが、フォントが変わると即あふれる
  # 状態を通してしまうため、実測の余裕（52px）より控えめな値で線を引く。
  MIN_GAP_PX = 8

  setup do
    # routes は遅延ロード。先に読ませないと Devise のマッピングが空になる
    Rails.application.reload_routes_unless_loaded
    Warden.test_mode!

    @staff = User.create!(email: "staff-history@example.com", name: "スタッフ",
                          password: "password", user_type: "1")
    login_as @staff, scope: :user

    @patient = User.create!(email: "patient-history@example.com", name: "患者",
                            password: "password")
  end

  teardown do
    Warden.test_reset!
  end

  # ── 1. 前提の確認 ──────────────────────────────
  #
  # 以降のテストは「この表が table-layout:fixed で組まれている」ことが前提。
  # CSS が読まれていないと各 tr はただの行に戻り、width:1% は
  # 「最小幅 1%」として扱われて中身なりに広がる。つまり壊れた実装でも
  # 重ならなくなり、2〜4 が意味を失ったまま緑になる。
  # そうなっていないことを最初に確かめる。
  test "履歴テーブルが reserves.scss の table-layout:fixed を受けている" do
    make_questionnaire(submitted_at: Time.current)
    visit karte_user_path(@patient)

    row = rows.first

    assert_equal "table", row["display"],
                 "tr が display:table になっていない。application.css が読まれて " \
                 "いない可能性がある（yarn build:css を実行して再試行すること）"
    assert_equal "fixed", row["tableLayout"],
                 "tr が table-layout:fixed になっていない。application.css が読まれて " \
                 "いない可能性がある（yarn build:css を実行して再試行すること）"
  end

  # ── 2. 1件のときの座標 ─────────────────────────
  #
  # 2度目の再発はこの状態で見つかった。件数に関わらず同じ CSS で潰れるが、
  # 報告された条件をそのまま残しておく。
  test "問診票が1件のとき、日付が隣の様式セルに重ならない" do
    make_questionnaire(submitted_at: Time.current)
    visit karte_user_path(@patient)

    row = rows.first
    date, form = row["cells"][0], row["cells"][1]

    assert_no_overflow date
    assert_no_overlap date, form
  end

  # ── 3. 日付セルが指定どおりの幅を持っている ───────────
  #
  # width:1% に戻ると、この幅が 9px（＝1% × 900px）まで落ちる。
  # em で確かめるのは、ボックスモデル（bootstrap の border-box が
  # 効くかどうか）に左右されずに「14em を指定できているか」を見るため。
  test "日付セルが 14em ぶんの幅を持っている" do
    make_questionnaire(submitted_at: Time.current)
    visit karte_user_path(@patient)

    date = rows.first["cells"][0]
    expected = DATE_CELL_EM * date["fontSize"]

    assert_in_delta expected, date["borderBoxWidth"], 1.0,
                    "日付セルの幅が #{DATE_CELL_EM}em (#{expected}px) から外れている。" \
                    "実測 #{date['borderBoxWidth']}px。" \
                    "show.html.erb の width 指定が失われていないか確認すること"
  end

  # ── 4. 複数行でも列が揃う ──────────────────────
  #
  # bc9cf9c の table-layout:auto は、各 tr が独立した table ボックスに
  # なる構造を変えられないため、行ごとに列幅がばらついた（実測で最大54pxのズレ）。
  # 「重ならない」だけでは、その状態も通ってしまう。
  # 全行で日付列の幅と様式列の開始位置が一致することまで見る。
  test "複数行でも日付列の幅と様式列の開始位置が全行で揃う" do
    make_questionnaire(submitted_at: 1.day.ago)
    make_questionnaire(submitted_at: 3.months.ago)
    draft = MedicalQuestionnaire.create!(user: @patient, answers: {},
                                         form_version: MedicalQuestionnaireForm::VERSION)
    assert draft.status_draft?, "下書き（日付ではなく「下書き」と出る行）も混ぜて測る"

    visit karte_user_path(@patient)

    measured = rows
    assert_equal 3, measured.size

    widths = measured.map { |r| r["cells"][0]["borderBoxWidth"].round(2) }.uniq
    assert_equal 1, widths.size, "日付列の幅が行ごとにばらついている: #{widths.inspect}"

    lefts = measured.map { |r| r["cells"][1]["left"].round(2) }.uniq
    assert_equal 1, lefts.size, "様式列の開始位置が行ごとにずれている: #{lefts.inspect}"

    measured.each_with_index do |row, i|
      assert_no_overflow row["cells"][0], "#{i}行目: "
      assert_no_overlap row["cells"][0], row["cells"][1], "#{i}行目: "
    end
  end

  # ── 5. 計測そのものが退行を検知できることの確認 ──────────
  #
  # 2〜4 は「重なっていない」ことを見る。測り方を間違えていても緑になるため、
  # テスト自体が壊れていないことを言えない。
  # そこで width を 1% に差し替えて、狙った症状（セルが 9px に潰れ、
  # 日付が隣のセルへあふれて重なる）が実際に再現し、2〜4 と同じ判定が
  # 落ちる側に転ぶことを確認する。ここが落ちたら、上の緑は信用できない。
  test "width を 1% に差し替えると日付セルが潰れて重なる" do
    make_questionnaire(submitted_at: Time.current)
    visit karte_user_path(@patient)

    assert_no_overflow rows.first["cells"][0], "差し替え前: "

    shrink_date_cell_to_one_percent

    date, form = rows.first["cells"].first(2)

    assert_operator date["borderBoxWidth"], :<, 40,
                    "width:1% でも日付セルが潰れていない。table-layout:fixed が " \
                    "効いていない可能性がある（この状態では 2〜4 も無意味になる）"
    assert_operator date["scrollWidth"], :>, date["clientWidth"],
                    "width:1% でも日付があふれていない。計測が症状を捉えられていない"
    assert_operator date["textRight"], :>, form["textLeft"],
                    "width:1% でも日付が様式セルの文字に重なっていない。" \
                    "計測が症状を捉えられていない"
  end

  private

  def make_questionnaire(submitted_at:)
    questionnaire = MedicalQuestionnaire.new(
      user: @patient, answers: {}, form_version: MedicalQuestionnaireForm::VERSION
    )
    questionnaire.status = :submitted
    questionnaire.submitted_at = submitted_at
    questionnaire.save!
    questionnaire
  end

  def assert_no_overflow(cell, prefix = "")
    assert_operator cell["scrollWidth"], :<=, cell["clientWidth"],
                    "#{prefix}日付セルから中身があふれている" \
                    "（内容 #{cell['scrollWidth']}px / セル #{cell['clientWidth']}px）。" \
                    "show.html.erb の日付セルの width を確認すること"
  end

  def assert_no_overlap(date, form, prefix = "")
    gap = form["textLeft"] - date["textRight"]

    assert_operator gap, :>=, MIN_GAP_PX,
                    "#{prefix}日付と「様式」の文字の間隔が #{gap.round(2)}px しかない" \
                    "（日付の右端 #{date['textRight'].round(2)}px / " \
                    "様式の左端 #{form['textLeft'].round(2)}px）。" \
                    "0 以下なら重なっている"
  end

  # 提出履歴テーブルの各行を測る。
  # 表に id が無いため「問診票」の見出しを持つ section から辿る。
  # 文字の座標は Range で実際のグリフの矩形を取る。セルの矩形だけ見ていると、
  # あふれた文字が隣にかぶっていても気づけない。
  def rows
    page.evaluate_script(<<~JS)
      (() => {
        const heading = [...document.querySelectorAll('h3')]
          .find(el => el.textContent.trim() === '問診票');
        if (!heading) throw new Error('問診票の見出しが見つからない');
        const table = heading.parentElement.querySelector('table');
        if (!table) throw new Error('提出履歴のテーブルが見つからない');

        const textRect = (el) => {
          const range = document.createRange();
          range.selectNodeContents(el);
          const r = range.getBoundingClientRect();
          range.detach();
          return r;
        };

        return [...table.querySelectorAll('tr')].map((tr) => {
          const trStyle = getComputedStyle(tr);
          return {
            display: trStyle.display,
            tableLayout: trStyle.tableLayout,
            cells: [...tr.children].map((td) => {
              const rect = td.getBoundingClientRect();
              const text = textRect(td);
              return {
                text: td.textContent.trim(),
                left: rect.left,
                right: rect.right,
                borderBoxWidth: rect.width,
                clientWidth: td.clientWidth,
                scrollWidth: td.scrollWidth,
                fontSize: parseFloat(getComputedStyle(td).fontSize),
                textLeft: text.left,
                textRight: text.right
              };
            })
          };
        });
      })()
    JS
  end

  # 失われた修正と同じ状態を作る。ソースは触らず、同じ詳細度の
  # インラインスタイルを上書きして width だけ 1% に戻す。
  def shrink_date_cell_to_one_percent
    page.execute_script(<<~JS)
      const heading = [...document.querySelectorAll('h3')]
        .find(el => el.textContent.trim() === '問診票');
      heading.parentElement.querySelectorAll('table tr').forEach((tr) => {
        tr.children[0].style.width = '1%';
      });
    JS
  end
end

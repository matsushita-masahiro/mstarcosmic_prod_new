# test/controllers/karte/users_sort_test.rb
#
# カルテ管理一覧（/karte/users）の列ソート。
#
# 本番は1298件・26ページあるため、並べ替えは必ず SQL の ORDER BY で行う。
# 表示中の1ページだけを並べ替えても「生年月日の新しい順」にはならない。
# ここでは実際にリクエストを投げ、行の並び（＝発行された SQL の結果）を見る。
#
# 落ちたときに疑うところ:
#   「—」が先頭に来た → sort_expression の NULLIF か order_clause の NULLS LAST
#   ページ送りで人が重複・消失 → order_clause の第2キー（users.id）
#   並びが既定のまま変わらない → SORT_KEYS の綴りとヘッダーの key
require "test_helper"

class Karte::UsersSortTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Rails.application.reload_routes_unless_loaded

    @staff = User.create!(email: "staff-sort@example.com", name: "スタッフ",
                          password: "password", user_type: "1")
    sign_in @staff

    @document = ConsentDocument.create!(version: "sort-test", title: "同意書",
                                        body: "本文", published_at: Time.current)

    # 各列で並び順が入れ替わるように、値の大小をわざとバラバラにしてある。
    #        カナ         生年月日      性別  問診票  同意書
    # 甲: アイカワ    1990-01-01   女性   2件   署名済
    # 乙: イトウ      2000-05-05   男性   1件   未署名
    # 丙: （空欄）    （なし）     未登録 0件   未署名
    @kou = create_patient(name: "甲", name_kana: "アイカワ",
                          birthday: Date.new(1990, 1, 1), gender: "f")
    @otsu = create_patient(name: "乙", name_kana: "イトウ",
                           birthday: Date.new(2000, 5, 5), gender: "m")
    @hei = create_patient(name: "丙", name_kana: "", birthday: nil, gender: nil)

    2.times { MedicalQuestionnaire.create!(user: @kou) }
    MedicalQuestionnaire.create!(user: @otsu)

    Consent.create!(user: @kou, consent_document: @document,
                    agreed_at: Time.current, signature_strokes: [[1, 2]])
  end

  # ── 既定の並び（従来どおり） ─────────────────────

  test "並べ替えを指定しないと従来どおり会員No.の降順" do
    assert_equal ids(@hei, @otsu, @kou), listed_ids
  end

  # ── 6列それぞれで並ぶ ───────────────────────────

  test "会員No.で並ぶ" do
    assert_equal ids(@kou, @otsu, @hei), listed_ids(sort: "member_no", direction: "asc")
    assert_equal ids(@hei, @otsu, @kou), listed_ids(sort: "member_no", direction: "desc")
  end

  test "お名前はカナの五十音順で並ぶ" do
    # 漢字は 甲 < 丙 < 乙（コードポイント順）なので、
    # カナ（アイカワ → イトウ）で並んでいれば name_kana を見ている。
    assert_equal ids(@kou, @otsu), listed_ids(sort: "name", direction: "asc").first(2)
    assert_equal ids(@otsu, @kou), listed_ids(sort: "name", direction: "desc").first(2)
  end

  test "生年月日は初回クリックで新しい順" do
    assert_equal ids(@otsu, @kou), listed_ids(sort: "birthday").first(2)
    assert_equal ids(@kou, @otsu), listed_ids(sort: "birthday", direction: "asc").first(2)
  end

  test "性別は女性→男性の順で並ぶ" do
    assert_equal ids(@kou, @otsu), listed_ids(sort: "gender", direction: "asc").first(2)
    assert_equal ids(@otsu, @kou), listed_ids(sort: "gender", direction: "desc").first(2)
  end

  test "同意書は署名済が先頭に来る" do
    assert_equal @kou.id, listed_ids(sort: "consent").first
  end

  test "問診票は初回クリックで件数の多い順" do
    assert_equal ids(@kou, @otsu), listed_ids(sort: "questionnaire").first(2)
    assert_equal ids(@otsu, @kou), listed_ids(sort: "questionnaire", direction: "asc").first(2)
  end

  # ── 「—」は方向によらず最後 ─────────────────────

  test "値の無い行は昇順・降順のどちらでも最後に来る" do
    { "name" => "カナ空欄", "birthday" => "生年月日なし", "gender" => "性別未登録",
      "questionnaire" => "問診票0件" }.each do |key, label|
      %w[asc desc].each do |direction|
        assert_equal @hei.id, listed_ids(sort: key, direction: direction).last,
                     "#{key}（#{label}）の #{direction} で最後に来ていない"
      end
    end
  end

  # 同意書は署名済／未署名の2値しかないため、「未署名が最後」は
  # 「署名済がすべて先頭」と同じ意味になる。丙と乙のどちらが末尾かは
  # 決まらないので、署名済の甲が常に先頭に来ることで確かめる。
  test "未署名は昇順・降順のどちらでも署名済より後ろに来る" do
    %w[asc desc].each do |direction|
      assert_equal @kou.id, listed_ids(sort: "consent", direction: direction).first,
                   "同意書の #{direction} で署名済が先頭に来ていない"
    end
  end

  # ── ホワイトリスト ───────────────────────────

  test "許可していないソートキーは既定に落ちる" do
    ["users.id; DROP TABLE users --", "encrypted_password", "", "(SELECT 1)"].each do |bad|
      assert_equal ids(@hei, @otsu, @kou), listed_ids(sort: bad),
                   "#{bad.inspect} が既定に落ちていない"
      assert_equal 3, User.where(id: ids(@kou, @otsu, @hei)).count
    end
  end

  test "許可していない向きはその列の初回の向きに落ちる" do
    # 問診票の初回は降順（件数の多い順）
    assert_equal ids(@kou, @otsu),
                 listed_ids(sort: "questionnaire", direction: "; --").first(2)
  end

  # ── 検索・ページングとの併用 ─────────────────────

  test "検索で絞り込んでも並べ替えが効き、件数は検索結果のまま" do
    ids = listed_ids(q: "カ", sort: "name", direction: "asc")

    # 「カ」はアイカワ（甲）とイトウでない方…ではなく、カナ部分一致で甲のみ
    assert_equal [@kou.id], ids
  end

  test "ヘッダーのリンクが検索語を保ち、ページは1に戻す" do
    get karte_users_path(q: "アイカワ", sort: "member_no", direction: "desc", page: 3)

    link = header_link("生年月日")
    assert_includes link, "q=#{CGI.escape('アイカワ')}"
    assert_includes link, "sort=birthday"
    assert_includes link, "direction=desc" # 生年月日の初回は降順
    assert_not_includes link, "page="
  end

  test "同じ列のヘッダーは向きを反転させたリンクになる" do
    get karte_users_path(sort: "birthday", direction: "desc")
    assert_includes header_link("生年月日"), "direction=asc"

    get karte_users_path(sort: "birthday", direction: "asc")
    assert_includes header_link("生年月日"), "direction=desc"
  end

  test "ページ送りのリンクが検索語と並び順を引き継ぐ" do
    # 1ページに収まると前へ/次へが出ないため、2ページぶん用意する
    (Karte::UsersController::PER_PAGE + 1).times do |i|
      create_patient(name: "頁#{i}", name_kana: "ページ", birthday: nil, gender: "f")
    end

    get karte_users_path(q: "ページ", sort: "name", direction: "asc")
    nexts = css_select("a").map { |a| a["href"] }.select { |h| h.to_s.include?("page=2") }

    assert_predicate nexts, :any?, "次へのリンクが出ていない"
    assert_includes nexts.first, "q=#{CGI.escape('ページ')}"
    assert_includes nexts.first, "sort=name"
    assert_includes nexts.first, "direction=asc"
  end

  test "並べ替えても「カルテへ」のリンク先は変わらない" do
    get karte_users_path(sort: "birthday")

    assert_select "a[href=?]", karte_user_path(@kou), text: "カルテへ"
  end

  private

  def ids(*users) = users.map(&:id)

  def create_patient(attrs)
    User.create!(attrs.merge(email: "#{SecureRandom.hex(6)}@example.com",
                             password: "password"))
  end

  # 一覧に出ている行の user id を表示順のまま取り出す。
  # 各行末の「カルテへ」（/karte/users/:id）だけを拾う。
  # ヘッダーのソートリンクは /karte/users?… なのでここには入らない。
  def listed_ids(params = {})
    get karte_users_path(params)
    assert_response :success

    css_select("a").filter_map do |a|
      m = a["href"].to_s.match(%r{\A/karte/users/(\d+)\z})
      m && m[1].to_i
    end
  end

  def header_link(label)
    link = css_select("th a").find { |a| a.text.include?(label) }
    assert_not_nil link, "「#{label}」のヘッダーリンクが無い"
    link["href"]
  end
end

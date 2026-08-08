require "test_helper"

# 施術記録の専用画面（Karte::TreatmentNotesController）。
#
# ── このファイルが守っているもの ──────────────────────
#
# 1. カルテ詳細と専用画面の分離
#    施術メモは来店のたび、同意書・問診票は初回または改訂時と書く頻度が違う。
#    同じページに戻すとメモを書くだけのときに他をスクロールで通り過ぎることになる。
#    「カルテ詳細に節が無いこと」と「そこから専用画面へ行けること」は対で守る。
#
# 2. 記録・編集・削除のあと専用画面に戻ること
#    カルテ詳細へ戻すと、続けて次の来店ぶんを書くときに毎回たどり直しになる。
#
# 3. 監査ログが残ること
#    カルテの閲覧・変更は KarteAccessLog に残す前提で運用している。
#
# ── このテストの範囲外 ──────────────────────────────
# 検索の大小区別・記号の扱い、担当者名の控えは TreatmentNote モデルの担当
# （test/models/treatment_note_test.rb）。
# 権限（スタッフ以外が触れないこと）は Karte::BaseController の担当。
class KarteTreatmentNotesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    # routes は遅延ロードのため、先に読ませないと Devise.mappings が空で sign_in が落ちる
    Rails.application.reload_routes_unless_loaded

    @staff = User.create!(email: "staff-treatment-notes@example.com", name: "施術スタッフ",
                          password: "password", user_type: "10")
    @patient = User.create!(email: "patient-treatment-notes@example.com", name: "患者太郎",
                            password: "password", user_type: "12")
    sign_in @staff
  end

  # ── 1. カルテ詳細と専用画面の分離 ──────────────────

  test "カルテ詳細に施術メモの節は無く、専用画面へのボタンが出る" do
    create_note(body: "本日の施術内容")

    get karte_user_path(@patient)

    assert_response :success
    assert_no_match(/施術メモ/, response.body, "カルテ詳細に施術メモの節が残っています")
    assert_no_match(/本日の施術内容/, response.body, "カルテ詳細にメモ本文が出ています")
    assert_match(/施術記録へ/, response.body)
    assert_match(/#{Regexp.escape(karte_user_treatment_notes_path(@patient))}/, response.body,
                 "専用画面へのリンクがありません")
  end

  # ── 2. 専用画面 ────────────────────────────────

  test "専用画面に記録が並ぶ" do
    create_note(body: "本日の施術内容", ticket: "10回券 3回目")

    get karte_user_treatment_notes_path(@patient)

    assert_response :success
    assert_match(/本日の施術内容/, response.body)
    assert_match(/10回券 3回目/, response.body)
  end

  test "記録がなければその旨を出す" do
    get karte_user_treatment_notes_path(@patient)

    assert_response :success
    assert_match(/まだ施術メモがありません/, response.body)
  end

  # 禁忌の確認はカルテ詳細で行う運用のため、専用画面には出さない。
  test "専用画面に禁忌のバナーは出さない" do
    get karte_user_treatment_notes_path(@patient)

    assert_response :success
    assert_no_match(/施術できません/, response.body)
  end

  test "メモの中を検索できる" do
    create_note(body: "肩まわりを重点的に")
    create_note(body: "背中を中心に")

    get karte_user_treatment_notes_path(@patient, q: "肩")

    assert_response :success
    assert_match(/肩まわりを重点的に/, response.body)
    assert_no_match(/背中を中心に/, response.body)
  end

  test "検索で1件も出ないときは検索語を添えて伝える" do
    create_note(body: "肩まわりを重点的に")

    get karte_user_treatment_notes_path(@patient, q: "存在しない語")

    assert_response :success
    assert_match(/一致するメモはありません/, response.body)
  end

  # ── 3. 記録・編集・削除は専用画面に戻る ──────────────

  test "記録すると専用画面に戻る" do
    assert_difference "TreatmentNote.count", 1 do
      post karte_user_treatment_notes_path(@patient),
           params: { treatment_note: { visited_on: Date.current, ticket: "10回券 1回目",
                                       body: "本日の施術内容", author_name: @staff.name } }
    end

    assert_redirected_to karte_user_treatment_notes_path(@patient)
  end

  test "編集画面から専用画面に戻れる" do
    note = create_note(body: "本日の施術内容")

    get edit_karte_user_treatment_note_path(@patient, note)

    assert_response :success
    assert_match(/施術記録へ戻る/, response.body)
    assert_match(/#{Regexp.escape(karte_user_treatment_notes_path(@patient))}/, response.body)
  end

  test "更新すると専用画面に戻る" do
    note = create_note(body: "本日の施術内容")

    patch karte_user_treatment_note_path(@patient, note),
          params: { treatment_note: { visited_on: Date.current, ticket: "", body: "書き換え後" } }

    assert_redirected_to karte_user_treatment_notes_path(@patient)
    assert_equal "書き換え後", note.reload.body
  end

  test "更新に失敗したら編集画面のまま入力を残す" do
    note = create_note(body: "本日の施術内容")

    patch karte_user_treatment_note_path(@patient, note),
          params: { treatment_note: { visited_on: Date.current, ticket: "", body: "" } }

    assert_response :unprocessable_entity
    assert_equal "本日の施術内容", note.reload.body
  end

  test "削除すると専用画面に戻る" do
    note = create_note(body: "本日の施術内容")

    assert_difference "TreatmentNote.count", -1 do
      delete karte_user_treatment_note_path(@patient, note)
    end

    assert_redirected_to karte_user_treatment_notes_path(@patient)
  end

  # ── 4. 監査ログ ────────────────────────────────

  test "閲覧と変更が karte_access_logs に残る" do
    get karte_user_treatment_notes_path(@patient)
    assert_equal "notes_index", KarteAccessLog.last.action

    post karte_user_treatment_notes_path(@patient),
         params: { treatment_note: { visited_on: Date.current, ticket: "",
                                     body: "本日の施術内容", author_name: @staff.name } }
    assert_equal "note_create", KarteAccessLog.last.action
    note = TreatmentNote.last

    get edit_karte_user_treatment_note_path(@patient, note)
    assert_equal "note_edit", KarteAccessLog.last.action

    patch karte_user_treatment_note_path(@patient, note),
          params: { treatment_note: { visited_on: Date.current, ticket: "", body: "書き換え後" } }
    assert_equal "note_update", KarteAccessLog.last.action

    delete karte_user_treatment_note_path(@patient, note)
    assert_equal "note_destroy", KarteAccessLog.last.action
  end

  private

  def create_note(body: nil, ticket: nil)
    @patient.treatment_notes.create!(visited_on: Date.current, body: body,
                                     ticket: ticket, author: @staff)
  end
end

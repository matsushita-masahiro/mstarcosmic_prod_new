# test/models/treatment_note_test.rb
#
# 施術メモの記録としての性質を守るテスト。
#
# 【何を守るか】
# ・担当者名の控え — スタッフの User が消えても、誰が施術したかは残す
# ・空レコードの排除 — 日付だけの記録は意味がない
# ・検索 — 手書きをやめてキーボード入力にした理由そのもの
#
# 【このテストの範囲外】
# 権限（スタッフ以外が触れないこと）は Karte::BaseController の担当。
require "test_helper"

class TreatmentNoteTest < ActiveSupport::TestCase
  test "担当者名は記録時に控えられる" do
    note = build_note
    note.save!

    assert_equal note.author.name, note.author_name
  end

  test "担当者の User が消えても記録と担当者名は残る" do
    note = build_note
    note.save!
    author = note.author

    author.destroy

    note.reload
    assert_nil note.author_id, "author_id が nullify されていません"
    assert note.author_name.present?, "担当者名の控えが失われています"
    assert_equal "本日の施術内容", note.body
  end

  test "メモも券も空なら保存できない" do
    note = build_note(body: nil, ticket: nil)

    assert_not note.valid?
    assert note.errors[:base].any?
  end

  test "券だけの記録は保存できる" do
    # 来店したが特記事項なし、という記録に意味があるため
    note = build_note(body: nil, ticket: "10回券 3回目")
    assert note.valid?, note.errors.full_messages.join(" / ")
  end

  test "日付が無ければ保存できない" do
    note = build_note(visited_on: nil)
    assert_not note.valid?
  end

  test "本文で検索できる" do
    patient = create_patient
    hit  = build_note(user: patient, body: "塩を試してもらった").tap(&:save!)
    miss = build_note(user: patient, body: "特記事項なし").tap(&:save!)

    found = patient.treatment_notes.search("塩")
    assert_includes found, hit
    assert_not_includes found, miss
  end

  test "券欄でも検索できる" do
    patient = create_patient
    hit = build_note(user: patient, ticket: "10回券 3回目", body: nil).tap(&:save!)

    assert_includes patient.treatment_notes.search("10回券"), hit
  end

  test "英字は大文字小文字を区別せず引ける" do
    # 券名もメモ本文も自由記入で "VIP"/"vip" のような揺れが避けられない。
    # カルテ一覧の検索（氏名・カナ・電話）が ILIKE なのでそれに揃える。
    patient = create_patient
    upper = build_note(user: patient, body: "VIP対応").tap(&:save!)
    lower = build_note(user: patient, body: "ems 30分", ticket: nil).tap(&:save!)

    assert_includes patient.treatment_notes.search("vip"), upper
    assert_includes patient.treatment_notes.search("EMS"), lower
  end

  test "検索語の記号は文字として扱われる" do
    patient = create_patient
    build_note(user: patient, body: "経過は良好").tap(&:save!)

    # % は LIKE のワイルドカードだが、検索語として渡された場合は
    # 文字そのものとして扱われ、全件ヒットにならないこと
    assert_empty patient.treatment_notes.search("%")
  end

  test "新しい来店が上に並ぶ" do
    patient = create_patient
    old    = build_note(user: patient, visited_on: 3.days.ago.to_date).tap(&:save!)
    recent = build_note(user: patient, visited_on: Date.current).tap(&:save!)

    assert_equal [recent, old], patient.treatment_notes.latest_first.to_a
  end

  test "患者を消すと施術メモも消える" do
    note = build_note
    note.save!
    patient = note.user

    assert_difference -> { TreatmentNote.count }, -1 do
      patient.destroy
    end
  end

  private

  def create_user(name:, user_type:)
    User.create!(name: name, user_type: user_type,
                 email: "note-test-#{SecureRandom.hex(6)}@example.com",
                 password: SecureRandom.hex(12))
  end

  def create_patient
    create_user(name: "テスト患者", user_type: "2")
  end

  def create_staff
    create_user(name: "テスト担当", user_type: "10")
  end

  def build_note(**attrs)
    defaults = {
      user: attrs.key?(:user) ? attrs[:user] : create_patient,
      author: create_staff,
      visited_on: Date.current,
      body: "本日の施術内容"
    }
    TreatmentNote.new(defaults.merge(attrs))
  end
end

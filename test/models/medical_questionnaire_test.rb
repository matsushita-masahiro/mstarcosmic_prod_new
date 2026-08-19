# test/models/medical_questionnaire_test.rb
#
# latest_first の並びを守るテスト。
#
# 【何を守るか】
# 提出時刻が同値のときの順序。ここが不定だと User#latest_questionnaire が
# 古い版を返し、カルテ画面の禁忌警告（show.html.erb の contraindicated?）が
# 出ないことがある。同時刻は訂正の再提出や紙カルテの一括取り込みで実際に起きる。
#
# 落ちたときは scope の第2キー（id DESC）が外れていないか見ること。
# UserKarte#latest_finalized_questionnaire も同じ並びを Ruby 側で再現しており、
# 片方だけ直すと一覧と詳細で別の問診票が出る。両者の一致は UserTest が見る。
#
# あわせて finalized（下書き以外）の範囲も守る。status に値が増えたとき、
# 新しい値が最新版の判定から漏れないことを確かめる。
require "test_helper"

class MedicalQuestionnaireTest < ActiveSupport::TestCase
  test "提出時刻が同値なら id の大きい方が先頭に来る" do
    patient = create_patient
    at = Time.current

    older = create_questionnaire(patient, submitted_at: at)
    newer = create_questionnaire(patient, submitted_at: at)

    assert_operator newer.id, :>, older.id, "テストの前提（id が昇順）が崩れています"
    assert_equal [ newer, older ], patient.medical_questionnaires.latest_first.to_a
  end

  test "提出時刻が違えば新しい方が先頭に来る" do
    patient = create_patient
    old    = create_questionnaire(patient, submitted_at: 3.days.ago)
    recent = create_questionnaire(patient, submitted_at: Time.current)

    assert_equal [ recent, old ], patient.medical_questionnaires.latest_first.to_a
  end

  test "未提出は created_at で並び、同値なら id の大きい方が先頭に来る" do
    # COALESCE(submitted_at, created_at) の後段。下書きは submitted_at が nil なので
    # created_at で並ぶが、同一秒に2件作られると同じくタイブレークが要る。
    patient = create_patient
    at = Time.current

    older = create_questionnaire(patient, status: :draft, submitted_at: nil, created_at: at)
    newer = create_questionnaire(patient, status: :draft, submitted_at: nil, created_at: at)

    assert_equal [ newer, older ], patient.medical_questionnaires.latest_first.to_a
  end

  test "finalized は下書き以外をすべて含む" do
    # submitted / reviewed を列挙せず draft を除く形にしている理由がここ。
    # status に値が増えても、この assert は追加した値を自動で拾う。
    patient = create_patient
    draft = create_questionnaire(patient, status: :draft, submitted_at: nil)
    expected = MedicalQuestionnaire.statuses.keys - [ "draft" ]

    kept = expected.map { |st| create_questionnaire(patient, status: st) }

    finalized = patient.medical_questionnaires.finalized
    kept.each { |q| assert_includes finalized, q, "status #{q.status} が finalized から漏れています" }
    assert_not_includes finalized, draft
  end

  test "最新版が reviewed でも latest_first の先頭に来る" do
    patient = create_patient
    old_submitted = create_questionnaire(patient, submitted_at: 3.days.ago)
    reviewed = create_questionnaire(patient, status: :reviewed, submitted_at: Time.current)

    assert_equal [ reviewed, old_submitted ],
                 patient.medical_questionnaires.finalized.latest_first.to_a
  end

  private

  def create_patient
    User.create!(name: "テスト患者", user_type: "2",
                 email: "mq-test-#{SecureRandom.hex(6)}@example.com",
                 password: SecureRandom.hex(12))
  end

  def create_questionnaire(user, **attrs)
    defaults = { status: :submitted, submitted_at: Time.current, answers: {} }
    user.medical_questionnaires.create!(defaults.merge(attrs))
  end
end

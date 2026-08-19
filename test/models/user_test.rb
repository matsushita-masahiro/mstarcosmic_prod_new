# test/models/user_test.rb
#
# 「最新の問診票」を返す2つの経路が食い違わないことを守るテスト。
#
# ・User#latest_questionnaire           … SQL 側（latest_first）。カルテ詳細の禁忌警告が使う
# ・User#latest_submitted_questionnaire … Ruby 側（N+1 回避のため一覧が使う）
#
# 実装が別々なので、片方だけ直すと一覧と詳細で別の版が出る。
# 落ちたときはどちらかのタイブレークが外れている。両方を揃えて直すこと。
require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "提出時刻が同値でも一覧と詳細が同じ問診票を指す" do
    patient = create_patient
    at = Time.current

    older = create_questionnaire(patient, submitted_at: at)
    newer = create_questionnaire(patient, submitted_at: at)

    assert_operator newer.id, :>, older.id, "テストの前提（id が昇順）が崩れています"

    patient.reload
    assert_equal newer, patient.latest_questionnaire
    assert_equal newer, patient.latest_submitted_questionnaire
    assert_equal patient.latest_questionnaire, patient.latest_submitted_questionnaire
  end

  test "提出時刻が違うときも一覧と詳細が同じ問診票を指す" do
    patient = create_patient
    create_questionnaire(patient, submitted_at: 3.days.ago)
    recent = create_questionnaire(patient, submitted_at: Time.current)

    patient.reload
    assert_equal recent, patient.latest_questionnaire
    assert_equal recent, patient.latest_submitted_questionnaire
  end

  test "下書きはどちらの経路でも最新として拾わない" do
    patient = create_patient
    submitted = create_questionnaire(patient, submitted_at: 3.days.ago)
    create_questionnaire(patient, status: :draft, submitted_at: nil)

    patient.reload
    assert_equal submitted, patient.latest_questionnaire
    assert_equal submitted, patient.latest_submitted_questionnaire
  end

  private

  def create_patient
    User.create!(name: "テスト患者", user_type: "2",
                 email: "user-test-#{SecureRandom.hex(6)}@example.com",
                 password: SecureRandom.hex(12))
  end

  def create_questionnaire(user, **attrs)
    defaults = { status: :submitted, submitted_at: Time.current, answers: {} }
    user.medical_questionnaires.create!(defaults.merge(attrs))
  end
end

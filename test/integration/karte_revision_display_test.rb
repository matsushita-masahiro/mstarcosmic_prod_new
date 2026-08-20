require "test_helper"

# カルテ詳細で、訂正版であることが分かるようにする。
#
# ── なぜ要るか ────────────────────────────────
#
# 訂正版は前版を書き換えず新しい版として並ぶため、履歴だけを見ると
# 「8/3 の訂正」と「2回目の来店で取り直した問診」が同じに見える。
# 前者なら 8/3 の内容が訂正されたということ、後者なら別の機会の問診で、
# 施術判断の意味がまったく違う。
#
# ── 警告バナーの原則（最重要）──────────────────────
#
# 出すのは「訂正された」という事実だけで、前版の警告そのものは出さない。
# 「ペースメーカー装着」を再掲すると、施術者は現在も装着していると誤読する。
# 伝えたいのは逆で、前版の警告はもう当てはまらないかもしれないから
# 前版を見て判断してほしい、ということ。
#
# 出す条件は「施術可否に関わる項目が変わったとき」だけ。
#   出しすぎ → 誤字の訂正でも毎回出て常態化し、本番で誰も読まなくなる
#   出さなすぎ → 「ペースメーカーあり → なし」が誰にも伝わらない
# この2つが同時に成立していることを見る。
#
# 判定そのものは test/models/questionnaire_revision_diff_test.rb が担当する。
# ここは「画面に出るか」を見る。
class KarteRevisionDisplayTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Rails.application.reload_routes_unless_loaded

    @staff = User.create!(email: "staff-revision-display@example.com", name: "スタッフ",
                          password: "password", user_type: "1")
    @patient = User.create!(email: "patient-revision-display@example.com", name: "患者",
                            password: "password", user_type: "2")
    sign_in @staff
  end

  # ── 履歴 ──────────────────────────────────

  test "履歴に訂正版であることと、どの版の訂正かが出る" do
    previous = create_questionnaire(submitted_at: Time.zone.local(2026, 8, 3, 10, 0))
    create_revision(previous, submitted_at: Time.zone.local(2026, 8, 20, 10, 0))

    get karte_user_path(@patient)

    assert_response :success
    assert_match(%r{08/03\s*の訂正（2版目）}, response.body,
                 "履歴に訂正であることが出ていません")
  end

  test "独立した提出には訂正の表示が出ない" do
    create_questionnaire(submitted_at: 5.days.ago)
    create_questionnaire(submitted_at: 1.day.ago)

    get karte_user_path(@patient)

    assert_response :success
    assert_no_match(/の訂正（/, response.body,
                    "訂正でない版に訂正の表示が出ています")
  end

  # ── 警告バナー ────────────────────────────

  test "禁忌が あり から なし に変わった訂正でバナーが出る" do
    previous = create_questionnaire(answers: { "q10_pacemaker" => "yes" },
                                    submitted_at: Time.zone.local(2026, 8, 3, 10, 0))
    create_revision(previous, answers: { "q10_pacemaker" => "no" })

    get karte_user_path(@patient)

    assert_match(/訂正された問診票です/, response.body, "訂正のバナーが出ていません")
    assert_match(/施術可否に関わる項目が変更されています/, response.body)

    # 前版の警告を再掲しないこと。再掲すると「いま装着している」と誤読される。
    assert_no_match(/施術できません/, response.body,
                    "訂正で消えた禁忌の警告が残っています（現在装着中と誤読されます）")
  end

  # 誤字の訂正で毎回出ると常態化して読まれなくなる。
  test "禁忌に関わらない訂正ではバナーが出ない" do
    previous = create_questionnaire(
      answers: { "q10_pacemaker" => "no", "q7_marital_status" => "single" },
      submitted_at: 5.days.ago
    )
    create_revision(previous,
                    answers: { "q10_pacemaker" => "no", "q7_marital_status" => "married" })

    get karte_user_path(@patient)

    assert_no_match(/訂正された問診票です/, response.body,
                    "禁忌が変わっていないのにバナーが出ています")
  end

  # 赤が出ているときは施術が止まるので、その下に別の箱を重ねない。
  test "禁忌が なし から あり の場合は赤い警告だけが出る" do
    previous = create_questionnaire(answers: { "q10_pacemaker" => "no" },
                                    submitted_at: 5.days.ago)
    create_revision(previous, answers: { "q10_pacemaker" => "yes" })

    get karte_user_path(@patient)

    assert_match(/施術できません/, response.body, "赤い警告が出ていません")
    assert_no_match(/訂正された問診票です/, response.body,
                    "赤い警告と訂正のバナーが重複しています")
  end

  test "要確認のフラグが変わった訂正でもバナーが出る" do
    previous = create_questionnaire(answers: { "q10_other_device" => "yes" },
                                    submitted_at: 5.days.ago)
    create_revision(previous, answers: { "q10_other_device" => "no" })

    get karte_user_path(@patient)

    assert_match(/訂正された問診票です/, response.body)
  end

  # ── 差分 ──────────────────────────────────

  test "差分に旧値から新値が設問ラベルで出る" do
    previous = create_questionnaire(answers: { "q10_pacemaker" => "yes" },
                                    submitted_at: 5.days.ago)
    revision = create_revision(previous, answers: { "q10_pacemaker" => "no" })

    get karte_user_path(@patient, questionnaire_id: revision.id)

    assert_match(/訂正前（.*）\s*との違いを見る/m, response.body, "差分の折りたたみが出ていません")
    assert_match(/【10】/, response.body, "設問ラベルが出ていません")
    assert_match(/ペースメーカー装着/, response.body)
    assert_no_match(/q10_pacemaker/, response.body, "キー名が画面に露出しています")
  end

  test "独立した提出には差分が出ない" do
    questionnaire = create_questionnaire(submitted_at: 5.days.ago)

    get karte_user_path(@patient, questionnaire_id: questionnaire.id)

    assert_no_match(/との違いを見る/, response.body)
  end

  # ── 回帰 ──────────────────────────────────

  # 訂正版が1件も無い既存データで、表示が従来と変わらないこと。
  test "訂正が無い患者の表示は従来どおり" do
    create_questionnaire(answers: { "q10_pacemaker" => "yes" }, submitted_at: 5.days.ago)

    get karte_user_path(@patient)

    assert_response :success
    assert_match(/施術できません/, response.body, "従来の赤い警告が出ていません")
    assert_no_match(/訂正された問診票です/, response.body)
    assert_no_match(/の訂正（/, response.body)
    assert_no_match(/との違いを見る/, response.body)
  end

  test "問診票が無くても落ちない" do
    get karte_user_path(@patient)

    assert_response :success
  end

  private

  def create_questionnaire(answers: {}, submitted_at: Time.current, **attrs)
    @patient.medical_questionnaires.create!(
      status: :submitted, submitted_at: submitted_at, answers: answers,
      form_version: MedicalQuestionnaireForm::VERSION, **attrs
    )
  end

  def create_revision(previous, answers: {}, submitted_at: Time.current)
    create_questionnaire(answers: answers, submitted_at: submitted_at,
                         previous_version: previous)
  end
end

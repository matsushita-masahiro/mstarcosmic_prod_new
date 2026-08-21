require "test_helper"

# 会員（User）を削除できる条件。
#
# ── 削除が想定している場面 ────────────────────────
#
#   1. 登録内容を間違えたとき
#   2. 同じ人で2つアカウントを作ってしまったとき
#
# どちらも登録直後の掃除で、カルテの記録が積み上がる前の操作。
# 「間違いを無かったことにする」ものなので物理削除でよく、退会記録として
# 残す必要も無い。逆に言うと、記録が1件でもある会員はこの想定から外れる。
#
# ── なぜ判定を明示に置くのか ───────────────────────
#
# これまでは外部キー制約が偶然の防波堤になっていて、カルテ記録のある患者は
# 「消せなかった」だけだった。karte_access_logs に dependent: :destroy を
# 入れるとその壁が無くなり、問診票のある患者まで消せるようになる。
# 「登録間違いを消すつもりが、実は問診票のある患者だった」を防ぐため、
# 消してよいかの判断をモデルに置いている。
#
# ── 調査で実測した7パターンの固定 ──────────────────
#
#   A 何も無い患者           → 削除できる
#   B カルテを閲覧された患者 → 削除できる（関連を足したので閲覧ログも消える）
#   C 問診票あり             → 削除できない（判定で拒否）
#   D 訂正QRを発行された患者 → 削除できない（C に吸収される。下のコメント参照）
#   E 提出済み               → 削除できない（問診票があるため）
#   F スタッフ（発行者）     → 削除できない（issuer_id の外部キー。意図的に残す）
#   G スタッフ（確認者）     → 削除できる（reviewed_by_id を nullify にした）
class UserDeletionTest < ActiveSupport::TestCase
  setup do
    @staff = create_user(name: "スタッフ", user_type: "1")
  end

  # ── 削除できる ────────────────────────────
  test "A 記録の無い会員は削除できる" do
    patient = create_patient

    assert patient.destroy, "誤登録の掃除ができません"
    assert_not User.exists?(patient.id)
  end

  test "B カルテを閲覧された会員も削除できる" do
    patient = create_patient
    KarteAccessLog.record!(actor: @staff, patient: patient, action: "show")

    assert_difference -> { KarteAccessLog.count }, -1 do
      assert patient.destroy, "閲覧ログがあるだけで消せないままです"
    end
  end

  test "B 発行しただけの入場トークンは削除を妨げない" do
    patient = create_patient
    IntakeSession.issue!(patient: patient, issuer: @staff)

    assert_difference -> { IntakeSession.count }, -1 do
      assert patient.destroy
    end
  end

  # 誰が確認したかは失われるが、問診票そのものは残る。
  # 外部キーを on_delete: :nullify にしたので Rails 側に関連定義は要らない。
  test "G 問診票を確認したスタッフは削除できる（確認者は nil になる）" do
    reviewer = create_user(name: "確認者", user_type: "10")
    # 下書きから確定へ移すと署名の検証が走るので、確定済みから確認済みへ動かす。
    questionnaire = create_questionnaire(create_patient, status: :submitted,
                                         submitted_at: 1.day.ago)
    questionnaire.update!(reviewed_by: reviewer, status: :reviewed)

    assert reviewer.destroy, "確認したことがあるだけで消せないままです"
    assert_nil questionnaire.reload.reviewed_by_id
    assert questionnaire.persisted?, "問診票まで消えています"
  end

  # ── 削除できない ───────────────────────────
  test "C 問診票のある会員は削除できない" do
    patient = create_patient
    create_questionnaire(patient)

    assert_no_difference -> { User.count } do
      assert_not patient.destroy
    end
    assert_equal "この会員には問診票 1件の記録があるため削除できません",
                 patient.errors.full_messages.sole
  end

  test "同意書のある会員は削除できない" do
    patient = create_patient
    create_consent(patient)

    assert_not patient.destroy
    assert_equal "この会員には同意書 1件の記録があるため削除できません",
                 patient.errors.full_messages.sole
  end

  test "施術メモのある会員は削除できない" do
    patient = create_patient
    TreatmentNote.create!(user: patient, author: @staff, author_name: @staff.name,
                          visited_on: Date.current, body: "本日の施術内容")

    assert_not patient.destroy
    assert_equal "この会員には施術メモ 1件の記録があるため削除できません",
                 patient.errors.full_messages.sole
  end

  # 何がどれだけあるのかまで出す。「消せません」だけでは、
  # スタッフはどう対処すればよいのか分からない。
  test "拒否の理由は種類と件数で伝える" do
    patient = create_patient
    2.times { create_questionnaire(patient) }
    create_consent(patient)

    assert_not patient.destroy
    assert_equal "この会員には問診票 2件・同意書 1件の記録があるため削除できません",
                 patient.errors.full_messages.sole
  end

  # 【17】D にあたる。訂正QRは問診票がないと発行できないので、
  # 「訂正QRを発行された患者」は必ず問診票を持つ。外部キーではなく
  # 問診票の判定で止まる（止まる理由が変わっただけで、結果は同じ）。
  test "D 訂正QRを発行された会員も、問診票があるので削除できない" do
    patient = create_patient
    questionnaire = create_questionnaire(patient, status: :submitted, submitted_at: 1.day.ago)
    IntakeSession.issue_revision!(patient: patient, issuer: @staff, target: questionnaire)

    assert_not patient.destroy
    assert_includes patient.errors.full_messages.sole, "問診票 1件"
  end

  # 一方で、問診票そのものを消すときに入場トークンが邪魔をしなくなった。
  # 以前は restrict で、訂正QRを発行済みの問診票を消せなかった。
  test "訂正QRが指している問診票を消すと、トークン側の参照が nil になる" do
    patient = create_patient
    questionnaire = create_questionnaire(patient, status: :submitted, submitted_at: 1.day.ago)
    session = IntakeSession.issue_revision!(patient: patient, issuer: @staff, target: questionnaire)

    assert questionnaire.destroy
    assert_nil session.reload.target_questionnaire_id
    assert session.persisted?, "入場トークンまで消えています"
  end

  # スタッフは物理削除しない運用にする。「誰がQRを発行したか」「誰が見たか」を
  # 消せてしまうと、監査の記録として意味が無くなる。
  # 関連定義をあえて足していないので、外部キーで止まる。
  test "F 入場トークンを発行したスタッフは削除できない" do
    patient = create_patient
    IntakeSession.issue!(patient: patient, issuer: @staff)

    assert_raises(ActiveRecord::InvalidForeignKey) { @staff.destroy }
  end

  test "カルテを閲覧したスタッフは削除できない" do
    patient = create_patient
    KarteAccessLog.record!(actor: @staff, patient: patient, action: "show")

    assert_raises(ActiveRecord::InvalidForeignKey) { @staff.destroy }
    assert_equal 1, KarteAccessLog.count, "誰が見たかの記録が消えています"
  end

  # ── 削除したあと ───────────────────────────
  test "削除した会員の記録が孤児として残らない" do
    patient = create_patient
    PatientProfile.create!(user: patient)
    IntakeSession.issue!(patient: patient, issuer: @staff)
    KarteAccessLog.record!(actor: @staff, patient: patient, action: "show")
    id = patient.id

    assert patient.destroy

    assert_empty PatientProfile.where(user_id: id)
    assert_empty IntakeSession.where(user_id: id)
    assert_empty KarteAccessLog.where(patient_id: id)
  end

  # ── 訂正の鎖は restrict のまま ──────────────────
  #
  # 訂正版が指している版を消せないのは正しい。記録の整合性そのもの。
  # Rails 経由では has_one :revised_version, dependent: :nullify が先に
  # 参照を外すので、DB の制約が生きていることは delete で確かめる。
  test "訂正版が指している版は DB の制約で消せない" do
    patient = create_patient
    previous = create_questionnaire(patient, status: :submitted, submitted_at: 2.days.ago)
    create_questionnaire(patient, status: :submitted, previous_version: previous)

    assert_raises(ActiveRecord::InvalidForeignKey) do
      MedicalQuestionnaire.where(id: previous.id).delete_all
    end
  end

  private

  def create_user(name:, user_type: "2")
    User.create!(name: name, user_type: user_type,
                 email: "deletion-#{SecureRandom.hex(6)}@example.com",
                 password: SecureRandom.hex(12))
  end

  def create_patient = create_user(name: "テスト患者")

  def create_questionnaire(patient, **attrs)
    patient.medical_questionnaires.create!(
      { form_version: MedicalQuestionnaireForm::VERSION }.merge(attrs)
    )
  end

  def create_consent(patient)
    document = ConsentDocument.create!(
      version: "deletion-#{SecureRandom.hex(4)}", title: "同意書", body: "本文",
      published_at: Time.current
    )
    Consent.create!(user: patient, consent_document: document, agreed_at: Time.current,
                    signer_name: "テスト患者",
                    signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ])
  end
end

require "test_helper"

# 問診票履歴の「修正」ボタンを、系列の末端にだけ出す。
#
# 1つの版に訂正版を並列にぶら下げることはできない
# （MedicalQuestionnaire#revision_does_not_branch）。古い版のボタンを押しても
# IntakeSession.issue_revision! が finalized_revision_tip で末端に読み替えるため、
# 全行に出すと「この版を直せる」と読めて、押した本人が気づかないまま
# 別の版を起点にすることになる。
#
# 画面とサーバの判断がずれないよう、判定は issue_revision! が対象を決めるのと
# 同じ finalized_revision_tip で行っている。ここではその結果を見る。
class KarteQuestionnaireReviseButtonTest < ActionDispatch::IntegrationTest
  setup do
    @staff = User.create!(email: "rb-staff@example.com", name: "スタッフ",
                          password: "password", user_type: "1")
    @patient = User.create!(email: "rb-patient@example.com", name: "患者",
                            password: "password", user_type: "2")
    sign_in @staff
  end

  # ── 1. 版が3つある患者 ───────────────────────
  test "版が3つある系列では末端にだけ修正ボタンが出る" do
    v1 = submitted(at: 5.days.ago)
    v2 = revision_of(v1, at: 3.days.ago)
    v3 = revision_of(v2, at: 1.day.ago)

    get karte_user_path(@patient)

    assert_revise_button_on [ v3 ]
    assert_no_revise_button_on [ v1, v2 ]
  end

  # 古い版を開いていても、ボタンの出し先は変わらない。
  # 「いま見ている版を直す」ではなく「系列の末端を直す」ため。
  test "古い版を開いていても末端にだけ出る" do
    v1 = submitted(at: 5.days.ago)
    v2 = revision_of(v1, at: 3.days.ago)

    get karte_user_path(@patient, questionnaire_id: v1.id)

    assert_revise_button_on [ v2 ]
    assert_no_revise_button_on [ v1 ]
  end

  # ── 2. 版が1つだけの患者 ──────────────────────
  test "版が1つだけでもその行に修正ボタンが出る" do
    v1 = submitted(at: 1.day.ago)

    get karte_user_path(@patient)

    assert_revise_button_on [ v1 ]
  end

  # 独立した提出は、それぞれが自分の系列の末端。
  # 末端だけに絞ったことで「2回目の来店で取り直した問診」が
  # 直せなくなっていないことを確かめる。
  test "独立した提出はそれぞれにボタンが出る" do
    first  = submitted(at: 10.days.ago)
    second = submitted(at: 2.days.ago)

    get karte_user_path(@patient)

    assert_revise_button_on [ first, second ]
  end

  # ── 3. 下書きしかない患者 ─────────────────────
  #
  # finalized_revision_tip は自分自身（下書き）を返すので、
  # 末端かどうかの判定だけでは弾けない。下書きを除く条件が要る。
  test "下書きしかない患者にはボタンが出ない" do
    draft = draft_questionnaire

    get karte_user_path(@patient)

    assert_response :success
    assert_no_revise_button_on [ draft ]
    assert_select "form[action*='intake_sessions']", 1,
                  "「問診票の記入を開始」以外に修正ボタンが出ています"
  end

  # ── 4. 末端が下書きの場合 ─────────────────────
  #
  # finalized_revision_tip は下書きの手前で止まるので、直前の確定版が末端になる。
  # 下書き自身にはボタンを出さない（提出していない版を訂正しても意味がない）。
  test "末端が下書きなら直前の確定版にボタンが出る" do
    v1 = submitted(at: 5.days.ago)
    v2 = revision_of(v1, at: 3.days.ago)
    v3 = draft_questionnaire(previous: v2)

    get karte_user_path(@patient)

    assert_revise_button_on [ v2 ]
    assert_no_revise_button_on [ v1, v3 ]
  end

  private

  # button_to はフォームの action にパスを出す。
  # questionnaire_id はクエリ文字列に乗るので、それで版を見分ける。
  def revise_button_actions
    css_select("form[action*='questionnaire_id']").map { |f| f["action"] }
  end

  def assert_revise_button_on(questionnaires)
    actions = revise_button_actions
    questionnaires.each do |q|
      assert actions.any? { |a| a.include?("questionnaire_id=#{q.id}") },
             "id=#{q.id}（revision #{q.revision}）に修正ボタンが出ていません: #{actions.inspect}"
    end
    assert_equal questionnaires.size, actions.size,
                 "修正ボタンの数が想定と違います: #{actions.inspect}"
  end

  def assert_no_revise_button_on(questionnaires)
    actions = revise_button_actions
    questionnaires.each do |q|
      assert actions.none? { |a| a.include?("questionnaire_id=#{q.id}") },
             "id=#{q.id}（revision #{q.revision}）に修正ボタンが出ています"
    end
  end

  def submitted(at:)
    @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, status: :submitted,
      submitted_at: at, answers: { "q10_pacemaker" => "no" }
    )
  end

  def revision_of(previous, at:)
    @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, status: :submitted,
      submitted_at: at, answers: { "q10_pacemaker" => "no" }, previous_version: previous
    )
  end

  def draft_questionnaire(previous: nil)
    @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, status: :draft,
      answers: {}, previous_version: previous
    )
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password" } }
  end
end

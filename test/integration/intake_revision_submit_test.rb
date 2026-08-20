require "test_helper"

# 訂正版の送信。前版を書き換えず、新しい版として保存されることを守る。
#
# ── ここが訂正機能の存在意義 ────────────────────────
#
# 病歴・服薬・ペースメーカーの有無で施術可否を判断している。
# 上書きすると「当時どう判断したか」の根拠が消える。
# 紙のカルテで修正液を使わず二重線を引くのと同じ考え方。
#
# したがって「前版が無傷であること」が最も重要な不変条件になる。
# answers / handwriting_entries / body_marks に加えて、
# 添付されている PNG（blob）が差し替わっていないことまで見る。
#
# blob の共有は静かに起きる。draft_snapshot が image を返していれば、
# 訂正版の送信でその data_url が再添付され、前版の画像まで巻き添えにしうる。
# A-1 で image を外したことがここで効いている。
#
# ── 版の選ばれ方 ──────────────────────────────
#
# 最新版の判定（v2 を訂正しても v3 のまま等）は test/models/user_test.rb、
# 系列が鎖になることは test/models/medical_questionnaire_revision_test.rb。
# ここは「送信でどんなレコードができるか」だけを見る。
class IntakeRevisionSubmitTest < ActionDispatch::IntegrationTest
  # 1x1 の PNG
  PNG_DATA_URL = "data:image/png;base64," \
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

  STROKES = [ { "points" => [ { "x" => 10, "y" => 10, "time" => 1, "pressure" => 0.5 } ] } ].freeze

  setup do
    Rails.application.reload_routes_unless_loaded
    host! "intake.localhost"

    @document = ConsentDocument.create!(
      version: "revision-submit-test", title: "同意書", body: "本文", published_at: Time.current
    )
    @issuer  = User.create!(email: "issuer-rev-submit@example.com", name: "発行者", password: "password")
    @patient = User.create!(email: "patient-rev-submit@example.com", name: "患者", password: "password")
    Consent.create!(
      user: @patient, consent_document: @document, agreed_at: Time.current,
      signer_name: "患者", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
  end

  test "訂正を送ると新しい版ができ、前版はそのまま残る" do
    previous = create_previous_version

    enter_revision(previous)
    submit(answers: { "q7_marital_status" => "married" },
           handwriting: { "q1_purpose" => keyboard_entry("直したあとの内容") })

    assert_response :created

    revision = latest_version
    assert_not_equal previous.id, revision.id, "前版が上書きされています"
    assert_equal previous, revision.previous_version
    assert_equal 2, revision.revision
    assert_equal "married", revision.answers["q7_marital_status"]

    previous.reload
    assert_equal "single", previous.answers["q7_marital_status"], "前版の回答が書き換わっています"
    assert_equal "直す前の内容",
                 previous.handwriting_entries.find_by(question_key: "q1_purpose").transcribed_text,
                 "前版の手書きが書き換わっています"
    assert_equal 1, previous.body_marks.count, "前版の人体図が書き換わっています"
    assert_equal 1, previous.revision
  end

  # blob の共有・差し替えが起きていないこと。
  test "訂正しても前版の手書き画像が差し替わらない" do
    previous = create_previous_version
    original_blob_id = previous.handwriting_entries.find_by(question_key: "q3_history").image.blob.id

    enter_revision(previous)
    submit(answers: {},
           handwriting: { "q3_history" => pen_entry(STROKES) })

    entry = previous.reload.handwriting_entries.find_by(question_key: "q3_history")
    assert entry.image.attached?, "前版の画像が外れています"
    assert_equal original_blob_id, entry.image.blob.id, "前版の画像が差し替わっています"

    revised_entry = latest_version.handwriting_entries.find_by(question_key: "q3_history")
    assert_not_equal original_blob_id, revised_entry.image.blob.id,
                     "訂正版が前版と同じ blob を掴んでいます"
  end

  test "訂正版も submit! を通り、確定版として保存される" do
    previous = create_previous_version

    enter_revision(previous)
    submit(answers: {})

    revision = latest_version
    assert revision.status_submitted?, "訂正版が確定版になっていません"
    assert_not_nil revision.submitted_at, "submitted_at が入っていません（submit! を経由していない）"
    assert_equal @intake_session, revision.intake_session
  end

  # 訂正で「あり → なし」に変わったら、訂正版のフラグは false になること。
  test "禁忌フラグが訂正版でも組み直される" do
    previous = create_previous_version(answers: { "q10_pacemaker" => "yes" })
    assert previous.has_pacemaker, "前提: 前版で禁忌が立っていること"

    enter_revision(previous)
    submit(answers: { "q10_pacemaker" => "no" })

    assert_not latest_version.has_pacemaker, "訂正版のフラグが組み直されていません"
    assert previous.reload.has_pacemaker, "前版のフラグまで変わっています"
  end

  test "送信するとトークンが失効する" do
    previous = create_previous_version

    enter_revision(previous)
    submit(answers: {})

    assert_not @intake_session.reload.active?
  end

  # 訂正では同意書を経由しない。
  # 同意書を改訂して publish すると current が切り替わり、過去に署名した
  # 患者も全員が未署名扱いになるため、「前版があるなら署名済み」は成り立たない。
  test "同意書が改訂されて未署名扱いでも訂正画面が開く" do
    previous = create_previous_version
    @document.update!(archived_at: Time.current)
    ConsentDocument.create!(version: "revision-submit-test-v2", title: "同意書",
                            body: "改訂した本文", published_at: Time.current)
    assert_not Consent.current_for?(@patient), "前提: 未署名扱いになっていること"

    enter_revision(previous)

    get intake_questionnaire_path
    assert_response :success, "訂正なのに同意書へ送り返されています"
  end

  test "初回記入は従来どおり未署名なら同意書へ送られる" do
    @document.update!(archived_at: Time.current)
    ConsentDocument.create!(version: "revision-submit-test-v3", title: "同意書",
                            body: "改訂した本文", published_at: Time.current)

    session = IntakeSession.issue!(patient: @patient, issuer: @issuer)
    get intake_entry_path(token: session.raw_token)

    get intake_questionnaire_path
    assert_redirected_to new_intake_consent_path
  end

  private

  def create_previous_version(answers: { "q7_marital_status" => "single" })
    questionnaire = @patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION,
      status: :submitted, submitted_at: 3.days.ago, answers: answers
    )
    questionnaire.handwriting_entries.create!(
      question_key: "q1_purpose", input_mode: :keyboard, transcribed_text: "直す前の内容"
    )
    pen = questionnaire.handwriting_entries.create!(
      question_key: "q3_history", input_mode: :pen, strokes: STROKES,
      canvas_width: 860, canvas_height: 140
    )
    KarteAttachment.attach!(record: pen, name: :image, data_url: PNG_DATA_URL,
                            user_id: @patient.id, label: "q3_history")
    questionnaire.body_marks.create!(side: :front, x: 0.4, y: 0.3, mark_type: :pain)
    questionnaire.reload
  end

  def enter_revision(target)
    @intake_session = IntakeSession.issue_revision!(
      patient: @patient, issuer: @issuer, target: target
    )
    get intake_entry_path(token: @intake_session.raw_token)
  end

  def latest_version
    @patient.medical_questionnaires.order(:id).last
  end

  def keyboard_entry(text) = { "mode" => "keyboard", "text" => text }

  def pen_entry(strokes)
    { "mode" => "pen", "strokes" => strokes, "image" => PNG_DATA_URL,
      "width" => 860, "height" => 140 }
  end

  def submit(answers: {}, handwriting: nil, body_marks: nil)
    params = { answers: answers.to_json }
    params[:handwriting] = handwriting.to_json unless handwriting.nil?
    params[:body_marks] = body_marks.to_json unless body_marks.nil?
    post intake_questionnaires_path, params: params
  end
end

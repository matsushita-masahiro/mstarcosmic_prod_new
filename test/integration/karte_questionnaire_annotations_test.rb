require "test_helper"

# カルテ側のスタッフ追記。書ける人・書けない人と、版をまたいだ表示を見る。
class KarteQuestionnaireAnnotationsTest < ActionDispatch::IntegrationTest
  setup do
    @staff   = create_user(email: "ka-staff@example.com",  name: "山田スタッフ", user_type: "1")
    @nurse   = create_user(email: "ka-nurse@example.com",  name: "鈴木施術者",   user_type: "10")
    @member  = create_user(email: "ka-member@example.com", name: "ただの会員",   user_type: "2")
    @patient = create_user(email: "ka-patient@example.com", name: "患者",        user_type: "2")
    @other   = create_user(email: "ka-other@example.com",  name: "別の患者",     user_type: "2")

    @questionnaire = create_questionnaire(@patient, answers: { "q1_purpose" => "肩こり" })
  end

  # ── 書ける人 ─────────────────────────────
  test "管理者は追記できる" do
    sign_in @staff
    assert_difference "QuestionnaireAnnotation.count", 1 do
      post_annotation(body: "電話で確認済み")
    end

    annotation = QuestionnaireAnnotation.last
    assert_equal @staff.id, annotation.staff_id
    assert_equal "電話で確認済み", annotation.body
  end

  # 全スタッフが書ける。権限は既存の authenticate_staff_user? に任せており、
  # 施術スタッフ（user_type "10"）も同じ扱いになる。
  test "施術スタッフも追記できる" do
    sign_in @nurse
    assert_difference "QuestionnaireAnnotation.count", 1 do
      post_annotation(body: "前回より可動域が広い")
    end

    assert_equal @nurse.id, QuestionnaireAnnotation.last.staff_id
  end

  # ── 書けない人 ────────────────────────────
  test "スタッフでない会員は追記できない" do
    sign_in @member
    assert_no_difference "QuestionnaireAnnotation.count" do
      post_annotation(body: "会員が書いた")
    end

    assert_redirected_to root_path
  end

  test "未ログインでは追記できない" do
    assert_no_difference "QuestionnaireAnnotation.count" do
      post_annotation(body: "未ログインが書いた")
    end
  end

  # 書いた人はログイン中の本人にする。パラメータで差し替えられると、
  # 他のスタッフの名前で申し送りを書けてしまう。
  test "staff_id をパラメータで送っても差し替わらない" do
    sign_in @staff
    post karte_user_questionnaire_annotations_path(@patient),
         params: { questionnaire_annotation: {
           medical_questionnaire_id: @questionnaire.id, question_key: "q1_purpose",
           body: "なりすまし", staff_id: @nurse.id
         } }

    assert_equal @staff.id, QuestionnaireAnnotation.last.staff_id
  end

  # URL の user_id を差し替えても、他人の問診票には書けないこと。
  test "他の患者の問診票には追記できない" do
    other_questionnaire = create_questionnaire(@other, answers: {})
    sign_in @staff

    assert_no_difference "QuestionnaireAnnotation.count" do
      post karte_user_questionnaire_annotations_path(@patient),
           params: { questionnaire_annotation: {
             medical_questionnaire_id: other_questionnaire.id,
             question_key: "q1_purpose", body: "他人の問診票へ"
           } }
    end

    assert_response :not_found
  end

  test "設問定義に無いキーでは作られない" do
    sign_in @staff
    assert_no_difference "QuestionnaireAnnotation.count" do
      post_annotation(question_key: "q99_nonexistent", body: "存在しない設問へ")
    end
  end

  # ── 表示 ────────────────────────────────
  test "書いた追記がカルテに出る" do
    create_annotation(@questionnaire, body: "電話で確認済み")
    sign_in @staff

    get karte_user_path(@patient, questionnaire_id: @questionnaire.id)

    assert_response :success
    assert_match(/電話で確認済み/, response.body)
    assert_match(/スタッフ追記：山田スタッフ/, response.body, "書いた人と日付の見出しが出ていません")
  end

  # 同じ設問に複数あるときは書かれた順に読ませる。
  # 順番が入れ替わると、あとから足した訂正の追記が先に来て意味が反転する。
  test "同じ設問の追記は時系列順に並ぶ" do
    create_annotation(@questionnaire, body: "最初の申し送り", created_at: 3.days.ago)
    create_annotation(@questionnaire, body: "次の申し送り",   created_at: 2.days.ago)
    create_annotation(@questionnaire, body: "最後の申し送り", created_at: 1.day.ago)
    sign_in @staff

    get karte_user_path(@patient, questionnaire_id: @questionnaire.id)

    positions = [ "最初の申し送り", "次の申し送り", "最後の申し送り" ].map { |t| response.body.index(t) }
    assert_none_nil positions
    assert_equal positions.sort, positions, "追記が時系列順に並んでいません"
  end

  # ── 追記ボタンの位置 ─────────────────────────
  #
  # 追記は消せない。押し間違いは訂正の追記を足すしかないので、
  # ボタンがどの設問のものかが読めることが仕様の一部になる。

  test "追記ボタンはその設問の回答の直後に出る" do
    questionnaire = create_questionnaire(
      @patient, answers: { "q0_blood_type" => "o", "q10_pacemaker" => "no" }
    )
    sign_in @staff

    get karte_user_path(@patient, questionnaire_id: questionnaire.id)

    text = Nokogiri::HTML(response.body).text
    blood_type   = text.index("血液型")
    blood_button = text.index("追記血液型") || text.index(/追記\s*血液型/)
    pacemaker    = text.index("【10】")

    assert_not_nil blood_button, "追記ボタンに設問名が添えられていません"
    assert_operator blood_type, :<, blood_button, "ボタンが回答より前に出ています"
    assert_operator blood_button, :<, pacemaker,  "ボタンが次の設問より後に出ています"
  end

  # 描かれていない設問のボタンだけが宙に浮くと、次の設問のものと読まれる。
  # _answer は未記入の設問を描かないので、そこにボタンを残さない。
  test "未記入の設問には追記ボタンを出さない" do
    questionnaire = create_questionnaire(@patient, answers: { "q10_pacemaker" => "no" })
    sign_in @staff

    get karte_user_path(@patient, questionnaire_id: questionnaire.id)

    forms = css_select("form[action*='questionnaire_annotations']")
    assert_equal 1, forms.size,
                 "回答のある設問は1つだけなのにボタンが #{forms.size} 個出ています"
  end

  # ただし追記が付いている設問は、未記入でもボタンごと消さない。
  # 消すと、書いた申し送りに追記を足せなくなる。
  test "未記入でも追記が付いていれば表示とボタンが残る" do
    questionnaire = create_questionnaire(@patient, answers: { "q10_pacemaker" => "no" })
    QuestionnaireAnnotation.create!(
      medical_questionnaire: questionnaire, question_key: "q3_history",
      body: "既往歴は口頭で確認済み", staff: @staff
    )
    sign_in @staff

    get karte_user_path(@patient, questionnaire_id: questionnaire.id)

    assert_match(/既往歴は口頭で確認済み/, response.body)
    assert_equal 2, css_select("form[action*='questionnaire_annotations']").size,
                 "追記が付いた未記入の設問にボタンが残っていません"
  end

  # 押す直前に、どの設問へ書くのかを確かめられること。
  test "フォームは開いた設問の question_key を送る" do
    questionnaire = create_questionnaire(@patient, answers: { "q10_pacemaker" => "no" })
    sign_in @staff

    get karte_user_path(@patient, questionnaire_id: questionnaire.id)

    keys = css_select("input[name='questionnaire_annotation[question_key]']").map { |i| i["value"] }
    assert_equal [ "q10_pacemaker" ], keys
  end

  # ── 版をまたいだ表示 ─────────────────────────
  #
  # v1 に書いた申し送りが、患者が v2 を出した瞬間に最新版の画面から
  # 消えてはいけない。過去版を開けば見えるとしても気づかれない。
  test "前の版に付いた追記も最新版の画面に出る" do
    create_annotation(@questionnaire, body: "初回に確認した既往歴")
    revision = create_revision(@questionnaire, answers: { "q1_purpose" => "腰痛" })
    sign_in @staff

    get karte_user_path(@patient, questionnaire_id: revision.id)

    assert_response :success
    assert_match(/初回に確認した既往歴/, response.body,
                 "前の版に付いた追記が最新版の画面から消えています")
  end

  # どの版に書かれたかを出す。書かないと、患者が訂正した内容への追記なのか
  # 訂正前への追記なのかが読めない。
  test "前の版に付いた追記には版が明示される" do
    create_annotation(@questionnaire, body: "初回に確認した既往歴")
    revision = create_revision(@questionnaire, answers: { "q1_purpose" => "腰痛" })
    sign_in @staff

    get karte_user_path(@patient, questionnaire_id: revision.id)

    assert_match(/第1版への追記/, response.body, "どの版への追記かが出ていません")
  end

  # 表示中の版に付いた追記には版を書かない。全部に付くと読む手がかりにならない。
  test "表示中の版に付いた追記には版を書かない" do
    revision = create_revision(@questionnaire, answers: { "q1_purpose" => "腰痛" })
    create_annotation(revision, body: "訂正後に確認した")
    sign_in @staff

    get karte_user_path(@patient, questionnaire_id: revision.id)

    assert_match(/訂正後に確認した/, response.body)
    assert_no_match(/第2版への追記/, response.body)
  end

  # 古い版を開いたときも、その系列の追記は揃って見える。
  test "古い版を開いてもあとの版の追記が見える" do
    create_annotation(@questionnaire, body: "初回の申し送り")
    revision = create_revision(@questionnaire, answers: { "q1_purpose" => "腰痛" })
    create_annotation(revision, body: "訂正後の申し送り")
    sign_in @staff

    get karte_user_path(@patient, questionnaire_id: @questionnaire.id)

    assert_match(/初回の申し送り/, response.body)
    assert_match(/訂正後の申し送り/, response.body)
  end

  private

  def assert_none_nil(positions)
    positions.each_with_index do |pos, i|
      assert_not_nil pos, "#{i + 1} 件目の追記が画面に出ていません"
    end
  end

  def create_user(email:, name:, user_type:)
    User.create!(email: email, name: name, password: "password", user_type: user_type)
  end

  def create_questionnaire(patient, answers:)
    patient.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, status: :submitted,
      submitted_at: 3.days.ago, answers: answers
    )
  end

  def create_revision(previous, answers:)
    previous.user.medical_questionnaires.create!(
      form_version: MedicalQuestionnaireForm::VERSION, status: :submitted,
      submitted_at: 1.day.ago, answers: answers, previous_version: previous
    )
  end

  def create_annotation(questionnaire, body:, **attrs)
    QuestionnaireAnnotation.create!(
      medical_questionnaire: questionnaire, question_key: "q1_purpose",
      body: body, staff: @staff, **attrs
    )
  end

  def post_annotation(body:, question_key: "q1_purpose")
    post karte_user_questionnaire_annotations_path(@patient),
         params: { questionnaire_annotation: {
           medical_questionnaire_id: @questionnaire.id,
           question_key: question_key, body: body
         } }
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password" } }
  end
end

require "application_system_test_case"

# 複数選択（checkboxes）の回答が、保存されてカルテに出るまでを通すテスト。
#
# ── なぜカルテ画面まで見るのか ──────────────────────
#
# 収集側（collectAnswers）だけを見るテストでは、今回の壊れ方を捕まえられない。
# name から answers のキーを取り出す置換が
#   /^answers\[|\]$/g
# になっており、"answers[q6_family_history][]" から
# "q6_family_history][" という壊れたキーを作って jsonb に保存していた。
#
# それでも intake 側は緑のままだった。復元セレクタが
#   [name^="answers[q6_family_history][]"]
# という前方一致で、壊れたキーからでも実際の input に当たっていたため、
# 「書く → リロード → 戻る」は成立していた。
#
# 壊れていたのはカルテ側で、answer_for("q6_family_history") が nil を返し、
#   【6】家族歴          → 行ごと消える
#   【15】ご希望の項目   → 「未選択」と表示される
# になっていた。どちらもスタッフには「聞いたが患者が答えなかった」に見える。
# 家族歴は施術判断に関わるため、記録としては最悪の壊れ方だった。
# 本番では問診票11件のうち10件が該当していた。
#
# したがって、この経路は「保存できたか」ではなく
# 「スタッフの画面に出たか」まで通さないと守れない。
#
# ── 落ちたときに疑うところ ──────────────────────────
#
#   カルテに値が出ない        → answers のキーを確かめる。"][" が付いていたら
#                               questionnaire_controller.js の answerKey()。
#   「未回答の項目があります」→ validateRequired() が複数選択に当たっていない。
#                               キーから name を組み立て直していないか確認する。
class Intake::QuestionnaireCheckboxAnswersTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Rails.application.reload_routes_unless_loaded
    Warden.test_mode!

    @original_app_host = Capybara.app_host
    @original_include_port = Capybara.always_include_port
    Capybara.always_include_port = true

    document = ConsentDocument.create!(
      version: "checkbox-system-test", title: "同意書", body: "本文",
      published_at: Time.current
    )
    issuer = User.create!(email: "issuer-checkbox@example.com", name: "発行者",
                          password: "password")
    @staff = User.create!(email: "staff-checkbox@example.com", name: "スタッフ",
                          password: "password", user_type: "1")

    # gender を埋めておく。未設定だと冒頭で性別を聞かれ、
    # さらに【13】妊娠中ですか（female_only かつ必須）の出し分けが絡んで、
    # このテストが見たいものと関係のないところで送信が止まる。
    @patient = User.create!(email: "patient-checkbox@example.com", name: "患者",
                            password: "password", gender: "m")

    Consent.create!(
      user: @patient, consent_document: document, agreed_at: Time.current,
      signer_name: "患者", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
    @intake_session = IntakeSession.issue!(patient: @patient, issuer: issuer)
  end

  teardown do
    Capybara.app_host = @original_app_host
    Capybara.always_include_port = @original_include_port
    Warden.test_reset!
  end

  test "複数選択の回答が正しいキーで保存され、カルテに出る" do
    visit_questionnaire

    # 【6】家族歴（show_when なし・常に出ている）
    check_option("q6_family_history", "糖尿病")
    check_option("q6_family_history", "癌")

    # 【15】ご希望の項目（show_when あり・「はい」で現れる）
    choose_radio("q15_other_advice", "yes")
    check_option("q15_items", "整体")

    answer_required
    submit_questionnaire

    questionnaire = @patient.medical_questionnaires.status_submitted.last
    assert questionnaire, "問診票が送信されていません"

    broken = questionnaire.answers.keys.select { |k| k.include?("][") }
    assert_empty broken,
                 "壊れたキーで保存されています: #{broken.inspect}（answerKey() を確認すること）"

    assert_equal %w[糖尿病 癌], questionnaire.answers["q6_family_history"]
    assert_equal %w[整体], questionnaire.answers["q15_items"]


    # ── ここからスタッフ側 ──────────────────────
    visit_karte(questionnaire)

    assert_text "ご家族の中に下記の病気にかかった事がある方はいらっしゃいますか？（自分から見て三親等）"
    assert_text "糖尿病、癌"
    assert_text "整体"
    assert_no_text "未選択"
  end

  # 必須の設問が複数選択になったときに備えて、判定そのものを見ておく。
  # キーを直したあと validateRequired() がキーから name を組み立て直していると、
  # 複数選択に当たらず「選んでいるのに未回答」になる。
  test "複数選択を選んだ状態が未回答と判定されない" do
    visit_questionnaire
    check_option("q6_family_history", "糖尿病")
    answer_required

    unanswered = page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="questionnaire"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'questionnaire');
        const block = document.querySelector('input[name="answers[q6_family_history][]"]')
                              .closest('.q-block');

        // この設問には「必須」が付いていないので、印を足して判定させる。
        const mark = document.createElement('span');
        mark.className = 'q-required';
        mark.textContent = '必須';
        block.querySelector('.q-label').appendChild(mark);

        return ctrl.validateRequired();
      })()
    JS

    assert_empty unanswered,
                 "選択済みの複数選択が未回答と判定されています: #{unanswered.inspect}"
  end

  private

  def visit_questionnaire
    Capybara.app_host = "http://intake.localhost"
    visit "/s/#{@intake_session.raw_token}"
    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'
  end

  # app_host を戻して主ドメインへ。intake.localhost とは別ドメインなので
  # 患者のセッション cookie はスタッフ側へ持ち越されない。
  def visit_karte(questionnaire)
    Capybara.app_host = @original_app_host
    login_as @staff, scope: :user

    # questionnaire_id を付けると「すべての回答を見る」が開いた状態で出る。
    visit karte_user_path(@patient, questionnaire_id: questionnaire.id)
  end

  def check_option(key, value)
    find(%(input[name="answers[#{key}][]"][value="#{value}"])).click
  end

  def choose_radio(key, value)
    find(%(input[name="answers[#{key}]"][value="#{value}"])).click
  end

  # 【10】ペースメーカー。必須なので答えないと送信できない。
  def answer_required
    choose_radio("q10_pacemaker", "no")
  end

  def submit_questionnaire
    click_on "記入内容を送信する"
    assert_text "ありがとうございました", wait: 10
  end
end

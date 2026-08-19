require "application_system_test_case"

# 自動保存が手書き・人体図をサーバへ送っていることを、実ブラウザで確かめる。
#
# ── なぜ実ブラウザで測るのか ────────────────────────
#
# 手書き・人体図はブラウザ側の Stimulus コントローラが持っており、
# サーバに届くかどうかは questionnaire_controller.js の autosave() が
# それらを FormData に積むかどうかで決まる。
# 以前はここで answers しか積んでおらず、下書きに手書きが残らなかった。
#
# リクエストテスト（intake_questionnaire_autosave_test.rb）は
# 「送られてきたら保存する／送られてこなければ消さない」というサーバ側の
# 約束を守るもので、JS が実際に送るかどうかは見ていない。
# 送信漏れは例外を出さず静かに起きるため、ここを実ブラウザで固定する。
#
# ── 落ちたときに疑うところ ──────────────────────────
#
#   questionnaire_controller.js の autosave() が handwriting / body_marks を
#   append しているか。空・差分無しのときに省く条件が広すぎないか。
class Intake::QuestionnaireAutosaveTest < ApplicationSystemTestCase
  setup do
    @original_app_host = Capybara.app_host
    @original_include_port = Capybara.always_include_port
    Capybara.always_include_port = true
    Capybara.app_host = "http://intake.localhost"

    document = ConsentDocument.create!(
      version: "autosave-system-test", title: "同意書", body: "本文",
      published_at: Time.current
    )
    issuer   = User.create!(email: "issuer-autosave-sys@example.com", name: "発行者", password: "password")
    @patient = User.create!(email: "patient-autosave-sys@example.com", name: "患者", password: "password")
    Consent.create!(
      user: @patient, consent_document: document, agreed_at: Time.current,
      signer_name: "患者", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )
    @intake_session = IntakeSession.issue!(patient: @patient, issuer: issuer)
  end

  teardown do
    Capybara.app_host = @original_app_host
    Capybara.always_include_port = @original_include_port
  end

  test "自動保存で手書きの内容がサーバの下書きに残る" do
    visit_questionnaire

    type_into_keyboard_pane("q1_purpose", "肩こりの相談です")
    trigger_autosave

    entry = wait_for { draft&.handwriting_entries&.find_by(question_key: "q1_purpose") }
    assert entry, "自動保存で手書きがサーバに届いていません（autosave が送っていない）"
    assert_equal "肩こりの相談です", entry.transcribed_text
  end

  test "自動保存で人体図のマーカーがサーバの下書きに残る" do
    visit_questionnaire

    mark_body_figure
    trigger_autosave

    assert wait_for { draft&.body_marks&.any? },
           "自動保存で人体図のマーカーがサーバに届いていません"
  end

  private

  def visit_questionnaire
    visit "/s/#{@intake_session.raw_token}"
    visit "/questionnaire"
    assert_selector '[data-handwriting-field-key-value="q1_purpose"]'
  end

  def draft
    @patient.medical_questionnaires.status_draft.first
  end

  # キーボードペインに入力する。ペン手書きは PNG を伴い実機依存が大きいので、
  # 「autosave が handwriting を積んでいるか」を見るにはこちらで十分。
  def type_into_keyboard_pane(key, text)
    field = %([data-handwriting-field-key-value="#{key}"])
    find(%(#{field} [data-handwriting-field-target="keyboardTab"])).click
    find(%(#{field} [data-handwriting-field-target="textarea"])).fill_in(with: text)
  end

  def mark_body_figure
    svg = first('[data-controller~="body-map"] svg')
    svg.click(x: 20, y: 30)
  end

  # 30秒待たずに autosave を1回だけ走らせる。間隔そのものは変更していない。
  def trigger_autosave
    page.execute_script(<<~JS)
      const el = document.querySelector('[data-controller~="questionnaire"]');
      const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'questionnaire');
      ctrl.dirty = true;
      ctrl.autosave();
    JS
  end

  def wait_for(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      result = yield
      return result if result
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
    end
    nil
  end
end

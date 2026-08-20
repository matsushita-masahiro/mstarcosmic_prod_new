require "application_system_test_case"

# 端末に残す下書き（localStorage）とサーバへ送る下書きの「中身の違い」を守るテスト。
#
# ── 守っている対はひとつ ────────────────────────
#
#   localStorage … strokes だけ。PNG は入れない。
#   サーバ送信   … PNG も送る。
#
# 片方だけ見ていると壊しても気づけないので、同じファイルに並べて置く。
#
# 【localStorage から PNG を外した理由】
# restore() は data.strokes からしか描き直しておらず、image はどこからも
# 参照されていない。復元に使われないものが容量だけを食っていた。
# iPhone は DPR 3 でキャンバスの実ピクセルが CSS サイズの3倍になるため
# PNG の base64 は1欄でも重く、手書き欄は最大13個ある。
# iOS Safari の上限（約5MB）を超えると QuotaExceededError が投げられ、
# その回の保存が丸ごと失敗する（一部だけ残ることはない）。
#
# 【PNG をサーバから消してはいけない理由・最重要】
# カルテ画面はペン欄を PNG で表示している（HandwritingEntry#image）。
# localStorage 側だけを見て collectHandwriting() の戻り値を書き換えると、
# 送信からも PNG が消え、カルテから手書きが消える。
# 画面上は何も起きないので、ここが唯一の検知点になる。
#
# 【このテストで捕まえられないこと】
# ヘッドレス Chrome の DPR は 1 で、実機（DPR 3）の容量とは桁が違う。
# 「PNG が入っていないこと」は守れるが、実機での容量そのものは測れない。
class Intake::QuestionnaireLocalDraftTest < ApplicationSystemTestCase
  setup do
    @original_app_host = Capybara.app_host
    @original_include_port = Capybara.always_include_port
    Capybara.always_include_port = true
    Capybara.app_host = "http://intake.localhost"

    document = ConsentDocument.create!(
      version: "local-draft-system-test", title: "同意書", body: "本文",
      published_at: Time.current
    )
    issuer   = User.create!(email: "issuer-local-draft@example.com", name: "発行者", password: "password")
    @patient = User.create!(email: "patient-local-draft@example.com", name: "患者", password: "password")
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

  test "ペンで書いても localStorage には PNG が入らない" do
    visit_questionnaire
    draw_with_pen("q1_purpose")

    assert wait_until { local_draft_has?("q1_purpose") }, "前提: localStorage に入ること"

    raw = raw_local_draft
    assert_not_includes raw, "data:image/png",
                        "localStorage に手書きの PNG が入っています（容量超過で下書きごと失われます）"

    entry = JSON.parse(raw)["handwriting"]["q1_purpose"]
    assert_not entry.key?("image"), "localStorage の手書きに image キーが残っています"
    assert entry["strokes"].present?,
           "strokes まで落ちています（これが無いとリロードで筆跡が戻りません）"
  end

  # 最重要。ここが落ちるとカルテ画面から手書き画像が消える。
  test "サーバへ送る手書きには PNG が残る" do
    visit_questionnaire
    draw_with_pen("q1_purpose")
    trigger_autosave

    entry = wait_for { draft&.handwriting_entries&.find_by(question_key: "q1_purpose") }
    assert entry, "前提: 自動保存でペンの欄がサーバに届くこと"
    assert entry.image.attached?,
           "サーバに PNG が届いていません（カルテ画面で手書きが表示されなくなります）"
  end

  # localStorage 用の加工が collectHandwriting() の戻り値を壊していないこと。
  # 壊すと送信側からも PNG が消えるが、端末側だけ見ていると気づけない。
  test "localStorage 用に image を除いても collectHandwriting() は PNG を返し続ける" do
    visit_questionnaire
    draw_with_pen("q1_purpose")

    assert has_image_after_local_save?("q1_purpose"),
           "localStorage 用の加工が collectHandwriting() の戻り値を書き換えています"
  end

  # 効果を数字で残す。修正前の形（image 込み）をその場で作って比べる。
  test "localStorage の下書きは PNG を含めた場合より小さい" do
    visit_questionnaire
    draw_with_pen("q1_purpose")
    assert wait_until { local_draft_has?("q1_purpose") }

    saved, with_image = draft_bytes

    assert_operator saved, :<, with_image,
                    "PNG を除いても容量が減っていません（saved=#{saved} with_image=#{with_image}）"
    puts "  [localStorage] 保存 #{saved} bytes / PNG 込みなら #{with_image} bytes " \
         "(#{(100.0 * saved / with_image).round(1)}%)"
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

  def field_script(key) = %([data-handwriting-field-key-value="#{key}"])

  def draw_with_pen(key)
    find(%(#{field_script(key)} [data-handwriting-field-target="penTab"])).click
    wait_until { canvas_width(key) > 0 }

    canvas = find(%(#{field_script(key)} [data-handwriting-field-target="canvas"]))
    page.driver.browser.action
        .move_to(canvas.native, 10, 10)
        .click_and_hold.move_by(40, 15).move_by(30, -10).release.perform
    assert wait_until { stroke_count(key) > 0 }, "前提: ペンで書けていること"
  end

  def canvas_width(key)
    page.evaluate_script(<<~JS)
      (() => {
        const c = document.querySelector('#{field_script(key)} [data-handwriting-field-target="canvas"]');
        return c ? c.width : -1;
      })()
    JS
  end

  def stroke_count(key)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('#{field_script(key)}');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'handwriting-field');
        return ctrl && ctrl.pad ? ctrl.pad.toData().length : -1;
      })()
    JS
  end

  def local_draft_has?(key)
    raw = raw_local_draft
    return false if raw.blank?
    JSON.parse(raw)["handwriting"]&.key?(key)
  rescue JSON::ParserError
    false
  end

  def raw_local_draft
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="questionnaire"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'questionnaire');
        return ctrl ? localStorage.getItem(ctrl.storageKeyValue) : null;
      })()
    JS
  end

  # localStorage への保存を挟んだうえで、送信用の収集に PNG が残っているかを見る。
  def has_image_after_local_save?(key)
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="questionnaire"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'questionnaire');
        ctrl.saveLocalDraft();
        const sent = ctrl.collectHandwriting()['#{key}'];
        return !!(sent && typeof sent.image === 'string' && sent.image.startsWith('data:image/png'));
      })()
    JS
  end

  # 実際に保存されたバイト数と、修正前の形（image 込み）のバイト数。
  def draft_bytes
    page.evaluate_script(<<~JS)
      (() => {
        const el = document.querySelector('[data-controller~="questionnaire"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'questionnaire');
        const saved = localStorage.getItem(ctrl.storageKeyValue);
        const withImage = JSON.stringify({
          savedAt: JSON.parse(saved).savedAt,
          answers: ctrl.collectAnswers(),
          handwriting: ctrl.collectHandwriting(),
          bodyMarks: ctrl.collectBodyMarks()
        });
        return [saved.length, withImage.length];
      })()
    JS
  end

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

  def wait_until(timeout: 5, &block) = !wait_for(timeout: timeout, &block).nil?
end

require "test_helper"

# 自動保存（PATCH /questionnaire）が手書き・人体図を落とさないことを守るテスト。
#
# ── なぜ必要か ────────────────────────────────
#
# 以前の autosave は answers しか送っておらず、下書きには選択式の回答しか
# 残らなかった（staging の実データで確認: 確定版は手書き4件・マーク2件、
# 同じ患者の下書きは 0件・0件）。
#
# 現行の運用ではサロンで一気に記入して送信するため被害は限定的だが、
# 前版の手書き・人体図を復元して編集する導線を作ると深刻になる。
# 患者が何も触らなくても、30秒後の自動保存で手書きの無い版が確定してしまう。
#
# ── ここで守るもの ────────────────────────────
#
# 1. autosave で手書き・人体図が保存される
# 2. **送られてこなかったものが消えない**（最重要）
#    autosave は差分の無いものを送らない。サーバがそれを「空になった」と
#    解釈すると、患者が触っていない記録が自動保存のたびに消える。
#    特に body_marks は destroy_all してから作り直すため、
#    空で呼ぶと全消しになる。
# 3. **届いて空なら消える**
#    「消す」ボタンで全部消したことがサーバに伝わること。
#    2 と 3 は逆方向の要求で、「キーが届かない」と「キーが届いて中身が空」を
#    区別できて初めて両立する。片方だけ通る実装にしないこと。
# 4. **partial が付いていれば削除しない**
#    端末が復元に失敗すると、画面は全欄の状態を表していない。
#    そのまま送るとサーバは足りないぶんを「患者が消した」と読み、
#    端末の不調がそのまま記録の削除になる。
#    クライアントが partial を付けて申告した場合は上書きだけする。
# 5. create（送信・確定）の全置換は従来どおり
#
# 落ちたときはテストを直さないこと。
# questionnaires_controller#update の「届いたキーだけ更新する」分岐と、
# questionnaire_controller.js の autosave が送るキーの両方を見ること。
class IntakeQuestionnaireAutosaveTest < ActionDispatch::IntegrationTest
  # 1x1 の PNG
  PNG_DATA_URL = "data:image/png;base64," \
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

  setup do
    Rails.application.reload_routes_unless_loaded
    # tld_length = 0 の設定なので、intake.example.com だと subdomain が
    # "intake.example" になり routes の constraints に当たらない。
    # システムテスト（Capybara.app_host）と同じ intake.localhost に合わせる。
    host! "intake.localhost"

    document = ConsentDocument.create!(
      version: "autosave-test", title: "同意書", body: "本文", published_at: Time.current
    )
    issuer   = User.create!(email: "issuer-autosave@example.com", name: "発行者", password: "password")
    @patient = User.create!(email: "patient-autosave@example.com", name: "患者", password: "password")
    Consent.create!(
      user: @patient, consent_document: document, agreed_at: Time.current,
      signer_name: "患者", signature_strokes: [ [ { "x" => 1, "y" => 1 } ] ]
    )

    @intake_session = IntakeSession.issue!(patient: @patient, issuer: issuer)
    get intake_entry_path(token: @intake_session.raw_token)
  end

  # ── 1. autosave で保存される ──────────────────
  test "自動保存で手書きが保存される" do
    autosave(handwriting: { "q1_purpose" => { "mode" => "keyboard", "text" => "肩こりの相談" } })
    assert_response :success

    entry = draft.handwriting_entries.find_by(question_key: "q1_purpose")
    assert entry, "自動保存で手書きが保存されていません"
    assert_equal "肩こりの相談", entry.transcribed_text
  end

  test "自動保存でペン手書きの筆跡と画像が保存される" do
    autosave(handwriting: {
      "q1_purpose" => { "mode" => "pen", "strokes" => [ [ { "x" => 1, "y" => 2 } ] ],
                        "image" => PNG_DATA_URL, "width" => 600, "height" => 160 }
    })
    assert_response :success

    entry = draft.handwriting_entries.find_by(question_key: "q1_purpose")
    assert entry.input_mode_pen?
    assert_equal 1, entry.strokes.size
    assert entry.image.attached?, "PNG が添付されていません"
  end

  test "自動保存で人体図のマーカーが保存される" do
    autosave(body_marks: [ { "side" => "front", "x" => 0.27, "y" => 0.45, "mark_type" => "pain" } ])
    assert_response :success

    assert_equal 1, draft.body_marks.count
    assert_in_delta 0.27, draft.body_marks.first.x, 0.001
  end

  # ── 2. 送られてこなかったものが消えない（最重要）──
  #
  # autosave は前回から変わっていないものを送らない。
  # 「送られてこなかった＝空になった」と解釈すると、患者が触っていない
  # 記録が自動保存のたびに消える。
  test "手書きを送らない自動保存でも既存の手書きは消えない" do
    autosave(handwriting: { "q1_purpose" => { "mode" => "keyboard", "text" => "肩こりの相談" } })

    # 以降の autosave は answers だけ（手書きに変更が無い状態）
    3.times { |i| autosave(answers: { "q8_per_day" => i.to_s }) }
    assert_response :success

    entry = draft.handwriting_entries.find_by(question_key: "q1_purpose")
    assert entry, "手書きを送らない自動保存で、既存の手書きが消えています"
    assert_equal "肩こりの相談", entry.transcribed_text
  end

  test "人体図を送らない自動保存でも既存のマーカーは消えない" do
    autosave(body_marks: [ { "side" => "front", "x" => 0.27, "y" => 0.45 },
                           { "side" => "back",  "x" => 0.5,  "y" => 0.6 } ])
    assert_equal 2, draft.body_marks.count

    3.times { |i| autosave(answers: { "q8_per_day" => i.to_s }) }
    assert_response :success

    assert_equal 2, draft.body_marks.count,
                 "人体図を送らない自動保存で、既存のマーカーが消えています"
  end

  # 2つ目の欄に書いた時点で、collectHandwriting() は両方のキーを含んだ
  # ハッシュを返す（「今この時点の全欄の状態」）。JS が片方だけ送ることはない。
  # 片方だけ届いた場合は「もう片方は消された」の意味になる（下の 3 を参照）。
  test "後から別の欄に書いても、先に書いた欄は残る" do
    autosave(handwriting: { "q1_purpose" => { "mode" => "keyboard", "text" => "1つ目" } })
    autosave(handwriting: {
      "q1_purpose"   => { "mode" => "keyboard", "text" => "1つ目" },
      "q16_concerns" => { "mode" => "keyboard", "text" => "2つ目" }
    })
    assert_response :success

    assert_equal 2, draft.handwriting_entries.count,
                 "後から別の欄に書いたときに、先の欄が消えています"
    assert_equal "1つ目", draft.handwriting_entries.find_by(question_key: "q1_purpose").transcribed_text
  end

  test "同じ欄を送り直すと上書きされる" do
    autosave(handwriting: { "q1_purpose" => { "mode" => "keyboard", "text" => "書きかけ" } })
    autosave(handwriting: { "q1_purpose" => { "mode" => "keyboard", "text" => "書き直した" } })

    assert_equal 1, draft.handwriting_entries.count, "同じ欄が二重に増えないこと"
    assert_equal "書き直した",
                 draft.handwriting_entries.find_by(question_key: "q1_purpose").transcribed_text
  end

  # ── 3. 届いて空なら消える ───────────────────────
  #
  # 2 とは逆方向の要求。「キーが届かない（＝変更なし）」と
  # 「キーが届いて中身が空（＝全部消した）」を区別できて初めて両立する。
  # ここと 2 の両方が緑であることに意味がある。
  test "空の handwriting が届くと既存の手書きが消える" do
    autosave(handwriting: { "q1_purpose" => { "mode" => "keyboard", "text" => "書いた" } })
    assert_equal 1, draft.handwriting_entries.count

    autosave(handwriting: {})
    assert_response :success

    assert_equal 0, draft.handwriting_entries.count,
                 "「消す」で全部消したことがサーバに伝わっていません"
  end

  test "空の body_marks が届くとマーカーが消える" do
    autosave(body_marks: [ { "side" => "front", "x" => 0.2, "y" => 0.3 } ])
    assert_equal 1, draft.body_marks.count

    autosave(body_marks: [])
    assert_response :success

    assert_equal 0, draft.body_marks.count,
                 "全マーカーを消したことがサーバに伝わっていません"
  end

  # collectHandwriting() は「今この時点の全欄の状態」を返し、空欄はキーごと落とす。
  # したがって一部だけ消した場合も、残った欄だけが届く。
  test "一部の欄だけ消すと、その欄だけが消えて他は残る" do
    autosave(handwriting: {
      "q1_purpose"   => { "mode" => "keyboard", "text" => "1つ目" },
      "q16_concerns" => { "mode" => "keyboard", "text" => "2つ目" }
    })
    assert_equal 2, draft.handwriting_entries.count

    # q1_purpose を消した状態（残った欄だけが届く）
    autosave(handwriting: { "q16_concerns" => { "mode" => "keyboard", "text" => "2つ目" } })
    assert_response :success

    keys = draft.handwriting_entries.pluck(:question_key)
    assert_equal [ "q16_concerns" ], keys,
                 "消した欄だけが消え、残した欄はそのままであること"
  end

  test "ペンの欄を消すと添付の PNG ごと消える" do
    autosave(handwriting: {
      "q1_purpose" => { "mode" => "pen", "strokes" => [ [ { "x" => 1, "y" => 2 } ] ],
                        "image" => PNG_DATA_URL, "width" => 600, "height" => 160 }
    })
    entry = draft.handwriting_entries.find_by(question_key: "q1_purpose")
    assert entry.image.attached?

    autosave(handwriting: {})
    assert_response :success

    assert_nil HandwritingEntry.find_by(id: entry.id), "ペンの欄が消えていません"
  end

  # ── 4. partial が付いていれば削除しない ───────────
  #
  # 3 とは逆で、「画面が空＝患者が消した」と読んではいけない場合。
  # 端末が復元に失敗したことをクライアントが申告してくる。
  # 3 と 4 の違いは partial の有無だけで、それ以外は同じリクエストになる。
  test "partial 付きなら、届かなかった欄を消さない" do
    autosave(handwriting: {
      "q1_purpose"   => { "mode" => "keyboard", "text" => "1つ目" },
      "q16_concerns" => { "mode" => "keyboard", "text" => "2つ目" }
    })
    assert_equal 2, draft.handwriting_entries.count

    # 復元に失敗した端末からの送信。q16 しか画面に無い
    autosave(handwriting: { "q16_concerns" => { "mode" => "keyboard", "text" => "2つ目" } },
             partial: true)
    assert_response :success

    assert_equal 2, draft.handwriting_entries.count,
                 "partial 付きなのに、復元できなかった欄が削除されています"
  end

  test "partial 付きでも、届いた欄の上書きは行う" do
    autosave(handwriting: { "q1_purpose" => { "mode" => "keyboard", "text" => "書きかけ" } })

    autosave(handwriting: { "q1_purpose" => { "mode" => "keyboard", "text" => "書き直した" } },
             partial: true)
    assert_response :success

    assert_equal "書き直した",
                 draft.handwriting_entries.find_by(question_key: "q1_purpose").transcribed_text,
                 "partial でも新しく書いたぶんは保存すること"
  end

  test "partial 付きで空が届いても消さない" do
    autosave(handwriting: { "q1_purpose" => { "mode" => "keyboard", "text" => "書いた" } })
    assert_equal 1, draft.handwriting_entries.count

    autosave(handwriting: {}, partial: true)
    assert_response :success

    assert_equal 1, draft.handwriting_entries.count,
                 "復元に失敗した端末の空を「全部消した」と読んではいけない"
  end

  # ── 5. create（送信）の回帰防止 ─────────────────
  test "送信では人体図が送られた内容で置き換わる" do
    autosave(body_marks: [ { "side" => "front", "x" => 0.1, "y" => 0.1 },
                           { "side" => "front", "x" => 0.2, "y" => 0.2 } ])
    assert_equal 2, draft.body_marks.count

    submit(body_marks: [ { "side" => "back", "x" => 0.9, "y" => 0.9 } ])
    assert_response :created
    assert draft, "送信しただけでは確定しない（署名まで下書きのまま）"

    confirm

    questionnaire = @patient.medical_questionnaires.reload.last
    assert questionnaire.status_submitted?
    assert_equal 1, questionnaire.body_marks.count, "送信時は送られた内容で全置換すること"
    assert questionnaire.body_marks.first.side_back?
  end

  test "送信では手書き・人体図・回答がまとめて確定する" do
    submit(
      answers: { "q10_pacemaker" => "yes" },
      handwriting: { "q1_purpose" => { "mode" => "keyboard", "text" => "確定版の記載" } },
      body_marks: [ { "side" => "front", "x" => 0.3, "y" => 0.4 } ]
    )
    assert_response :created
    confirm

    questionnaire = @patient.medical_questionnaires.reload.last
    assert questionnaire.status_submitted?
    assert questionnaire.has_pacemaker?, "フラグの昇格が従来どおり動くこと"
    assert_equal 1, questionnaire.handwriting_entries.count
    assert_equal 1, questionnaire.body_marks.count
  end

  private

  def draft
    @patient.medical_questionnaires.status_draft.first
  end

  # autosave（PATCH）。渡さなかったキーはリクエストに含めない。
  # これが「変わっていないものは送らない」JS 側の挙動に対応する。
  def autosave(answers: nil, handwriting: nil, body_marks: nil, partial: false)
    params = json_params(answers, handwriting, body_marks)
    params[:partial] = "1" if partial
    patch intake_questionnaire_path, params: params
  end

  # 送信（POST）。JS 側は3点セットを必ず送る。
  # ここでは確定しない。確認画面で署名するまで下書きのまま残る。
  def submit(answers: {}, handwriting: nil, body_marks: nil)
    post intake_questionnaires_path, params: json_params(answers, handwriting, body_marks)
  end

  # 確認画面での署名（POST）。submit! が走るのはここ。
  def confirm(signer_name: "患者")
    post intake_questionnaire_confirmation_path,
         params: { signer_name: signer_name, signer_relation: "self_signed",
                   signature_strokes: SIGNATURE_STROKES.to_json }
  end

  def json_params(answers, handwriting, body_marks)
    params = {}
    params[:answers] = answers.to_json unless answers.nil?
    params[:handwriting] = handwriting.to_json unless handwriting.nil?
    params[:body_marks] = body_marks.to_json unless body_marks.nil?
    params
  end
end

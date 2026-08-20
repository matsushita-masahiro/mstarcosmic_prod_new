import { Controller } from "@hotwired/stimulus"

// 入力が止まってから localStorage に書くまでの待ち。
// 連続入力のたびに手書き PNG を JSON 化すると重いので少し待つが、
// 端末が落ちたときに失う量を秒未満に抑えたいのでごく短くする。
const LOCAL_SAVE_DEBOUNCE_MS = 500

// 子コントローラの接続を待つ上限（requestAnimationFrame の回数）。
// 60fps で約2秒。ここまで待って揃わないのは JS エラーなど別の異常なので、
// 待ち続けずに揃ったぶんだけ復元する（何も戻らないよりはよい）。
// 復元しきれなかった場合は restoreVerified が false になり、
// autosave が削除方向の送信を控える。
const RESTORE_MAX_FRAMES = 120

// input の name 属性から answers のキーを取り出す。
//
//   "answers[q10_pacemaker]"       → "q10_pacemaker"
//   "answers[q6_family_history][]" → "q6_family_history"
//
// 【1つの正規表現でまとめないこと】
// 旧実装は /^answers\[|\]$/g で先頭と末尾を同時に剥がしていた。
// 複数選択の name は "…][]" で終わるため、"]" が末尾の1つだけ落ちて
// "q6_family_history][" という壊れたキーが残り、jsonb にそのまま保存された。
// （カルテ側の answer_for("q6_family_history") が nil になり、
//   家族歴が「答えていない」ように見えていた）
// 先頭と末尾は必ず別々に、末尾は "][]" を1かたまりとして剥がす。
function answerKey(name) {
  return name.replace(/^answers\[/, "").replace(/\](?:\[\])?$/, "")
}

// 問診票フォーム全体の制御。
//   - 開いたとき、端末（優先）またはサーバの下書きを画面に戻す
//   - 入力のたびに localStorage へ下書き保存（通信断でも記入内容が消えない）
//   - 30秒ごとにサーバへも下書きを送る（手書き・人体図は変わったときだけ）
//   - 性別に応じて女性専用設問を出し分ける
//   - 送信時に handwriting / body_marks を集約
export default class extends Controller {
  static targets = ["form", "status", "submit", "progress"]
  static values = {
    updateUrl: String,
    createUrl: String,
    storageKey: String,
    autosaveInterval: { type: Number, default: 30000 },

    // サーバに残っている下書き。localStorage と同じ形で ERB が埋める
    // （MedicalQuestionnaire#draft_snapshot）。端末に無いときだけ使う。
    // 戻せるものが無ければ属性ごと出ないので、hasServerDraftValue で判る。
    serverDraft: Object
  }

  connect() {
    this.submitting = false
    this.dirty = false

    // 前回 autosave で送った内容。次回はこれと同じなら送らない。
    // 手書きは PNG を含むので、変わっていないものを毎回送ると通信が重くなる。
    this.lastSentHandwriting = null
    this.lastSentBodyMarks = null

    // 画面の内容が「全欄の状態」として信用できるか。
    // 復元するものが無ければ最初から信用できる。
    this.restoreVerified = true

    this.restored = false
    this.restoreWhenReady()
    this.updateProgress()

    this.timer = setInterval(() => this.autosave(), this.autosaveIntervalValue)

    this.onInput = () => {
      this.dirty = true
      this.updateProgress()
      this.scheduleLocalSave()
    }
    this.element.addEventListener("input", this.onInput)
    this.element.addEventListener("change", this.onInput)
    this.element.addEventListener("handwriting-field:changed", this.onInput)
    this.element.addEventListener("body-map:changed", this.onInput)

    this.onBeforeUnload = (e) => {
      if (!this.dirty || this.submitting) return
      e.preventDefault()
      e.returnValue = ""
    }
    window.addEventListener("beforeunload", this.onBeforeUnload)
  }

  disconnect() {
    this.disconnected = true
    clearInterval(this.timer)
    clearTimeout(this.localSaveTimer)
    this.element.removeEventListener("input", this.onInput)
    this.element.removeEventListener("change", this.onInput)
    this.element.removeEventListener("handwriting-field:changed", this.onInput)
    this.element.removeEventListener("body-map:changed", this.onInput)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
  }

  // 冒頭で性別を選んだとき、女性専用設問を出し分ける
  genderChanged(event) {
    const isFemale = event.target.value === "female"
    this.femaleOnlySections().forEach((section) => {
      section.hidden = !isFemale
      if (!isFemale) {
        section.querySelectorAll("input, select, textarea").forEach((el) => {
          if (el.type === "radio" || el.type === "checkbox") el.checked = false
          else el.value = ""
        })
      }
    })
  }

  femaleOnlySections() {
    return Array.from(this.element.querySelectorAll('[data-female-only="true"]'))
  }

  // ── 収集 ────────────────────────────────────
  collectAnswers() {
    const answers = {}
    const fd = new FormData(this.formTarget)
    for (const [name, value] of fd.entries()) {
      const key = answerKey(name)
      if (name.endsWith("[]")) {
        answers[key] ||= []
        answers[key].push(value)
      } else {
        answers[key] = value
      }
    }
    return answers
  }

  collectHandwriting() {
    const result = {}
    this.handwritingControllers().forEach((ctrl) => {
      // 非表示の項目は送らない
      if (ctrl.element.closest("[hidden]")) return
      const data = ctrl.serialize()
      if (data) result[ctrl.keyValue] = data
    })
    return result
  }

  collectBodyMarks() {
    const ctrl = this.bodyMapController()
    return ctrl ? ctrl.serialize() : []
  }

  handwritingControllers() {
    return Array.from(this.element.querySelectorAll('[data-controller~="handwriting-field"]'))
      .map((el) => this.application.getControllerForElementAndIdentifier(el, "handwriting-field"))
      .filter(Boolean)
  }

  bodyMapController() {
    const el = this.element.querySelector('[data-controller~="body-map"]')
    return el ? this.application.getControllerForElementAndIdentifier(el, "body-map") : null
  }

  // ── 自動保存 ────────────────────────────────
  async autosave() {
    if (!this.dirty || this.submitting) return

    this.saveLocalDraft()

    try {
      const body = new FormData()
      body.append("answers", JSON.stringify(this.collectAnswers()))

      // 手書きと人体図も送る。送らないと下書きに残らず、記入途中で
      // 端末が落ちた場合や、前版を復元して編集した場合に消える。
      //
      // 省くのは「前回送ったものから変わっていない」ときだけ。
      // 空になった場合も、前回と違うなら送る。キーごと省くとサーバ側は
      // 「変更なし」として既存の記録を残すため、省いてしまうと
      // 「全部消した」を伝える手段が無くなる。
      //
      // 一度も書いていない欄のために毎回空を送ることにはならない。
      // lastSent* の初期値は null なので、初回だけ空が届き、
      // 2回目以降は同値でスキップされる。
      const handwriting = JSON.stringify(this.collectHandwriting())
      const bodyMarks = JSON.stringify(this.collectBodyMarks())
      const sendHandwriting = handwriting !== this.lastSentHandwriting

      // 復元に失敗した画面は「全欄の状態」を表していない。
      // そのまま送るとサーバは足りないぶんを「患者が消した」と読み、
      // 端末の不調がそのまま記録の削除になる。
      //
      // partial を付けると、サーバは上書きだけして削除しない。
      // 新しく書いたものは保存されるので、送信そのものは止めない。
      //
      // 人体図は全置換しか手段が無く、送ること自体が削除を含むので送らない。
      // （端末には残り、送信時の create でまとめて確定する）
      const sendBodyMarks = this.restoreVerified && bodyMarks !== this.lastSentBodyMarks

      if (sendHandwriting) body.append("handwriting", handwriting)
      if (sendBodyMarks) body.append("body_marks", bodyMarks)
      if (!this.restoreVerified) body.append("partial", "1")

      const res = await fetch(this.updateUrlValue, {
        method: "PATCH", body,
        headers: { "X-CSRF-Token": this.csrfToken(), "Accept": "application/json" }
      })

      if (res.ok) {
        // 送れたものだけ記録する。失敗した回は覚えないので次の autosave で送り直す。
        if (sendHandwriting) this.lastSentHandwriting = handwriting
        if (sendBodyMarks) this.lastSentBodyMarks = bodyMarks
        this.dirty = false
        this.setStatus("自動保存しました", "#6b7280")
      } else {
        this.setStatus("保存できませんでした（記入内容は端末に残っています）", "#b45309")
      }
    } catch (_e) {
      this.setStatus("通信できません（記入内容は端末に残っています）", "#b45309")
    }
  }

  // ── 復元の待ち合わせ ────────────────────────
  //
  // Stimulus は親コントローラの connect() が子より先に走ることがある。
  // その時点で handwritingControllers() は空配列を返すので、
  // restore() が誰にも届かず手書き・人体図だけが復元されない。
  // answers は DOM への直接代入なので成功し、「復元しました」も出るため、
  // 一見うまくいったように見える。
  //
  // 実機（iPhone）で発生し、ヘッドレス Chrome では接続が速く再現しない。
  // 6本目以降は「画面に無い＝患者が消した」と解釈するため、
  // 復元漏れがそのままサーバの削除になる。
  //
  // 待ち方は「DOM にある数だけコントローラが揃ったか」で判定する。
  // DOM の数は最初から確定しているので「いくつ揃えば完了か」が分かる。
  // 固定の setTimeout に頼らないのは、遅い端末で再び失敗するため。
  restoreWhenReady(frame = 0) {
    if (this.restored || this.disconnected) return

    if (this.childControllersReady() || frame >= RESTORE_MAX_FRAMES) {
      this.restored = true       // 復元は1回だけ。二重描画・上書きを避ける
      this.restoreDraft()
      return
    }

    requestAnimationFrame(() => this.restoreWhenReady(frame + 1))
  }

  childControllersReady() {
    const expected = this.element.querySelectorAll('[data-controller~="handwriting-field"]').length
    if (this.handwritingControllers().length < expected) return false

    const hasBodyMap = !!this.element.querySelector('[data-controller~="body-map"]')
    return !hasBodyMap || !!this.bodyMapController()
  }

  // ── localStorage ───────────────────────────
  //
  // サーバ送信（autosave）とは切り離して、入力のたびに書く。
  // localStorage への書き込みは通信を伴わないので 30 秒に律する理由がなく、
  // autosave 待ちの間に端末が落ちると直前 30 秒ぶんが失われていた。
  //
  // dirty はサーバ送信の要否を表すフラグなので意味を変えない。
  // ここは「端末に残す」だけで、送信の判断には関与しない。
  scheduleLocalSave() {
    clearTimeout(this.localSaveTimer)
    this.localSaveTimer = setTimeout(() => this.saveLocalDraft(), LOCAL_SAVE_DEBOUNCE_MS)
  }

  saveLocalDraft() {
    try {
      localStorage.setItem(this.storageKeyValue, JSON.stringify({
        savedAt: Date.now(),
        answers: this.collectAnswers(),
        handwriting: this.handwritingWithoutImages(),
        bodyMarks: this.collectBodyMarks()
      }))
    } catch (_e) {
      // 端末に保存できなかった（容量超過など）。
      //
      // サーバの下書きが受け皿になる（リロード時に読み込む）が、それは
      // autosave が届いたところまでで、直近の最大30秒ぶんはどこにも残らない。
      // 黙って失敗すると、患者は全部保存されているつもりで記入を続けるので、
      // 受け皿ができた今も伝え続ける。
      this.setStatus(
        "この端末に一時保存できませんでした。記入の途中でページを閉じないでください。",
        "#b45309"
      )
    }
  }

  // 端末に残すぶんからは手書きの PNG を除く。
  //
  // restore() は strokes からしか描き直しておらず、image はどこからも
  // 参照されていない。復元に使われないものが容量だけを食っている。
  // iPhone は DPR 3 でキャンバスの実ピクセルが CSS サイズの3倍になり、
  // PNG の base64 は1欄でも重い。手書き欄は最大13個ある。
  // iOS Safari の localStorage 上限（約5MB）を超えると QuotaExceededError で
  // その回の保存が丸ごと失敗する（一部だけ残ることはない）ため、
  // 手書きを多く書いた患者ほど下書きごと失いやすい形になっていた。
  //
  // サーバへは従来どおり PNG を送る。カルテ画面での表示に使うため。
  // したがって collectHandwriting() の戻り値そのものは書き換えず、
  // コピーを作ってそこから image を落とす。ここで元を壊すと
  // autosave / submit の送信からも PNG が消え、カルテに手書きが出なくなる。
  handwritingWithoutImages() {
    const copied = {}
    Object.entries(this.collectHandwriting()).forEach(([key, entry]) => {
      const { image: _image, ...withoutImage } = entry
      copied[key] = withoutImage
    })
    return copied
  }

  // 端末に残っていればそれを、無ければサーバの下書きを画面に戻す。
  //
  // localStorage を優先する。同じ端末で書き続けるのが主な使われ方で、
  // その場合は端末のほうが常に新しい（最後の autosave が届いていない
  // 最大30秒ぶんを持っている）。サーバの下書きは、端末に残っていなかった
  // ときの受け皿（別端末・容量超過・プライベートブラウズなど）。
  //
  // savedAt と updated_at の時刻比較はしない。端末の時計がずれていると
  // 誤判定するだけで、得るものが無い。
  //
  // 復元処理そのものは1本のまま。出所が変わるだけで、待ち合わせ
  // （restoreWhenReady）も自己検証（verifyRestore）も両方に効く。
  restoreDraft() {
    const local = this.localDraft()
    const draft = local || this.serverDraft()
    if (!draft) return

    Object.entries(draft.answers || {}).forEach(([key, value]) => {
      const fields = this.formTarget.querySelectorAll(`[name^="answers[${key}]"]`)
      fields.forEach((field) => {
        if (field.type === "radio" || field.type === "checkbox") {
          const values = Array.isArray(value) ? value : [value]
          field.checked = values.includes(field.value)
        } else {
          field.value = value
        }
      })
    })

    this.handwritingControllers().forEach((ctrl) => {
      ctrl.restore(draft.handwriting?.[ctrl.keyValue])
    })
    this.bodyMapController()?.restore(draft.bodyMarks)

    // 復元後に条件付き表示を再評価する（この後でないと hidden の判定がずれる）
    this.element.dispatchEvent(new Event("change", { bubbles: true }))

    this.verifyRestore(draft, local ? "local" : "server")
  }

  // 端末に残っている下書き。読めないもの・古いものは無かったことにする。
  localDraft() {
    let draft
    try {
      const raw = localStorage.getItem(this.storageKeyValue)
      if (!raw) return null
      draft = JSON.parse(raw)
    } catch (_e) {
      return null
    }

    // 24時間以上前の下書きは無視（別の来店時のものが残っている可能性）。
    // storageKey は患者ごとで来店ごとではないため、前回のものが端末に残る。
    if (!draft.savedAt || Date.now() - draft.savedAt > 86400000) {
      localStorage.removeItem(this.storageKeyValue)
      return null
    }

    return draft
  }

  // サーバに残っている下書き。HTML に埋まっていなければ何も返さない。
  //
  // こちらには24時間判定を入れない。サーバの下書きは intake_session に
  // 紐づいており、セッションは30分で失効するので古いものが降ってくる経路が無い。
  // 端末の時計に依存する判定を増やすと、時計がずれた端末で
  // 正しい下書きを捨てることになる。
  serverDraft() {
    if (!this.hasServerDraftValue) return null
    const draft = this.serverDraftValue
    return Object.keys(draft).length ? draft : null
  }

  // 保存されていたものが、実際に画面へ戻ったかを確かめる。
  //
  // 戻っていない欄があるまま autosave が走ると、サーバはそれを
  // 「患者が消した」と読んで削除する（6本目の意味論）。
  // 端末側の不調と患者の消去操作を取り違えないよう、ここで見分ける。
  //
  // source は文言を選ぶためだけに使う。判定は出所によらず同じで、
  // サーバから復元した場合も欠けていれば partial を付けて削除を控える。
  verifyRestore(draft, source) {
    const savedKeys = Object.keys(draft.handwriting || {})
    const savedMarks = (draft.bodyMarks || []).length

    const onScreen = Object.keys(this.collectHandwriting())
    const missing = savedKeys.filter((key) => !onScreen.includes(key))
    const marksMissing = savedMarks > 0 && this.collectBodyMarks().length === 0

    this.restoreVerified = missing.length === 0 && !marksMissing

    // 端末から戻したときは「前回の続き」だが、サーバから戻したときは
    // 患者にとって状況が違う（この端末には残っていなかった）。
    // 端末を前提にした言い方にすると、別端末で書き始めた患者に嘘になる。
    const fromServer = source === "server"

    if (this.restoreVerified) {
      this.setStatus(
        fromServer ? "保存されていた記入内容を読み込みました" : "前回の記入内容を復元しました",
        "#059669"
      )
      return
    }

    // 記録は守られる（削除は送らない）が、画面は欠けたままなので患者に伝える。
    this.setStatus(
      (fromServer ? "保存されていた記入内容" : "端末に保存されていた記入内容") +
      "の一部を読み込めませんでした。" +
      "空欄のところはお手数ですがもう一度ご記入ください。",
      "#b45309"
    )
  }

  clearLocalDraft() {
    try { localStorage.removeItem(this.storageKeyValue) } catch (_e) { /* noop */ }
  }

  // ── 提出 ────────────────────────────────────
  async submit() {
    if (this.submitting) return

    const missing = this.validateRequired()
    if (missing.length) {
      this.setStatus(`未回答の項目があります: ${missing.join("、")}`, "#dc2626")
      const first = this.formTarget.querySelector(`[name^="answers[${missing[0].key}]"]`)
      first?.closest(".q-block")?.scrollIntoView({ behavior: "smooth", block: "center" })
      return
    }

    this.submitting = true
    this.submitTarget.disabled = true
    this.setStatus("送信中…", "#6b7280")

    const body = new FormData()
    body.append("answers", JSON.stringify(this.collectAnswers()))
    body.append("handwriting", JSON.stringify(this.collectHandwriting()))
    body.append("body_marks", JSON.stringify(this.collectBodyMarks()))

    try {
      const res = await fetch(this.createUrlValue, {
        method: "POST", body,
        headers: { "X-CSRF-Token": this.csrfToken(), "Accept": "application/json" }
      })

      if (res.ok) {
        const { redirect_to } = await res.json()
        this.clearLocalDraft()
        this.dirty = false
        window.location.href = redirect_to
        return
      }

      const { errors } = await res.json().catch(() => ({ errors: ["送信に失敗しました"] }))
      this.setStatus(errors.join(" / "), "#dc2626")
    } catch (_e) {
      this.setStatus("通信に失敗しました。電波状況を確認して、もう一度お試しください。", "#dc2626")
    } finally {
      this.submitting = false
      this.submitTarget.disabled = false
    }
  }

  // 必須項目の検証。非表示の設問（女性専用など）は対象外にする。
  validateRequired() {
    const missing = []
    this.formTarget.querySelectorAll(".q-block").forEach((block) => {
      if (block.hidden) return
      const required = block.querySelector(".q-required")
      if (!required) return

      const input = block.querySelector('[name^="answers["]')
      if (!input) return

      // 選択済みの判定は input.name をそのまま使う。キーから組み立て直すと
      // 複数選択（name が "…][]"）に当たらず、選んでいても未回答になる。
      if (!block.querySelector(`[name="${input.name}"]:checked`)) {
        const key = answerKey(input.name)
        const label = block.querySelector(".q-label")?.textContent.trim().slice(0, 20)
        missing.push({ key, label })
      }
    })

    // 性別未選択のチェック（冒頭で聞いている場合のみ）
    const genderField = this.formTarget.querySelector('[name="answers[q0_gender]"]')
    if (genderField && !this.formTarget.querySelector('[name="answers[q0_gender]"]:checked')) {
      missing.unshift({ key: "q0_gender", label: "性別" })
    }

    return missing.map((m) => m.label || m.key)
  }

  updateProgress() {
    if (!this.hasProgressTarget) return
    const groups = new Set()
    this.formTarget.querySelectorAll('[name^="answers["]').forEach((el) => {
      if (el.closest("[hidden]")) return
      if (el.type === "radio" || el.type === "checkbox") {
        if (el.checked) groups.add(el.name)
      } else if (el.value.trim()) {
        groups.add(el.name)
      }
    })
    this.progressTarget.textContent = `${groups.size} 項目に回答済み`
  }

  csrfToken() {
    return document.querySelector("meta[name=csrf-token]")?.content
  }

  setStatus(text, color) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.style.color = color || "#6b7280"
  }
}

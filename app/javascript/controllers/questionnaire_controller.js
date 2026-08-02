import { Controller } from "@hotwired/stimulus"

// 問診票フォーム全体の制御。
//   - 30秒ごとに localStorage へ下書き保存（通信断でも記入内容が消えない）
//   - 同時にサーバへも下書きを送る
//   - 性別に応じて女性専用設問を出し分ける
//   - 送信時に handwriting / body_marks を集約
export default class extends Controller {
  static targets = ["form", "status", "submit", "progress"]
  static values = {
    updateUrl: String,
    createUrl: String,
    storageKey: String,
    autosaveInterval: { type: Number, default: 30000 }
  }

  connect() {
    this.submitting = false
    this.dirty = false

    this.restoreLocalDraft()
    this.updateProgress()

    this.timer = setInterval(() => this.autosave(), this.autosaveIntervalValue)

    this.onInput = () => { this.dirty = true; this.updateProgress() }
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
    clearInterval(this.timer)
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
      const key = name.replace(/^answers\[|\]$/g, "").replace(/\[\]$/, "")
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

      const res = await fetch(this.updateUrlValue, {
        method: "PATCH", body,
        headers: { "X-CSRF-Token": this.csrfToken(), "Accept": "application/json" }
      })

      if (res.ok) {
        this.dirty = false
        this.setStatus("自動保存しました", "#6b7280")
      } else {
        this.setStatus("保存できませんでした（記入内容は端末に残っています）", "#b45309")
      }
    } catch (_e) {
      this.setStatus("通信できません（記入内容は端末に残っています）", "#b45309")
    }
  }

  // ── localStorage ───────────────────────────
  saveLocalDraft() {
    try {
      localStorage.setItem(this.storageKeyValue, JSON.stringify({
        savedAt: Date.now(),
        answers: this.collectAnswers(),
        handwriting: this.collectHandwriting(),
        bodyMarks: this.collectBodyMarks()
      }))
    } catch (_e) {
      // 容量超過など。サーバ側の下書きが代替になるため握りつぶす。
    }
  }

  restoreLocalDraft() {
    let draft
    try {
      const raw = localStorage.getItem(this.storageKeyValue)
      if (!raw) return
      draft = JSON.parse(raw)
    } catch (_e) {
      return
    }

    // 24時間以上前の下書きは無視（別の来店時のものが残っている可能性）
    if (!draft.savedAt || Date.now() - draft.savedAt > 86400000) {
      localStorage.removeItem(this.storageKeyValue)
      return
    }

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

    // 復元後に条件付き表示を再評価する
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
    this.setStatus("前回の記入内容を復元しました", "#059669")
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
      const key = input.name.replace(/^answers\[|\]$/g, "")

      if (!block.querySelector(`[name="answers[${key}]"]:checked`)) {
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

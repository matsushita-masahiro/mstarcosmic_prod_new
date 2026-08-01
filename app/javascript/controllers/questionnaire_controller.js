import { Controller } from "@hotwired/stimulus"

// 問診票フォーム全体の制御。
//   - 30秒ごとに localStorage へ下書き保存（通信断でも記入内容が消えない）
//   - 同時にサーバへも下書きを送る（端末が変わっても復元できる）
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

    // 離脱時の警告
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

    // まず localStorage（通信不要・確実）
    this.saveLocalDraft()

    // 次にサーバ。失敗しても localStorage は残るので致命的ではない。
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
      // 容量超過など。無視して続行する（ペン画像が大きい場合に起きうる）
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
      // 記入内容は消さない。再送できるようにする。
      this.setStatus("通信に失敗しました。電波状況を確認して、もう一度お試しください。", "#dc2626")
    } finally {
      this.submitting = false
      this.submitTarget.disabled = false
    }
  }

  // 禁忌に関わる設問だけは必須にする
  validateRequired() {
    const required = [
      { key: "q10_pacemaker", label: "【10】医療機器" },
      { key: "q13_pregnant",  label: "【13】妊娠" }
    ]
    return required
      .filter(({ key }) => !this.formTarget.querySelector(`[name^="answers[${key}]"]:checked`))
      .map(({ label }) => label)
  }

  updateProgress() {
    if (!this.hasProgressTarget) return
    const groups = new Set()
    this.formTarget.querySelectorAll("[name^='answers[']:checked, [name^='answers[']").forEach((el) => {
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

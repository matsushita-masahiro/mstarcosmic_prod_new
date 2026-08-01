import { Controller } from "@hotwired/stimulus"
import SignaturePad from "signature_pad"

// iPad + Apple Pencil / 指での署名入力。
export default class extends Controller {
  static targets = ["canvas", "submit", "status"]
  static values = { submitUrl: String }

  connect() {
    this.pad = new SignaturePad(this.canvasTarget, {
      minWidth: 0.7,
      maxWidth: 2.6,
      throttle: 8,
      velocityFilterWeight: 0.6,
      penColor: "#111827",
      backgroundColor: "rgba(0,0,0,0)"   // 透過。台紙と合成できるようにする
    })

    this.penSeen = false
    this.submitting = false

    this.pad.addEventListener("endStroke", () => this.updateState())

    // パームリジェクション：一度でも Pencil が使われたら以降の指入力を無視
    this.onPointerDown = (event) => {
      if (event.pointerType === "pen") {
        this.penSeen = true
      } else if (this.penSeen) {
        event.stopPropagation()
        event.preventDefault()
      }
    }
    this.canvasTarget.addEventListener("pointerdown", this.onPointerDown, true)

    this.onResize = () => this.resize()
    window.addEventListener("resize", this.onResize)
    window.addEventListener("orientationchange", this.onResize)

    this.resize()
  }

  disconnect() {
    this.canvasTarget.removeEventListener("pointerdown", this.onPointerDown, true)
    window.removeEventListener("resize", this.onResize)
    window.removeEventListener("orientationchange", this.onResize)
    this.pad?.off()
  }

  // Retina 対応。canvas の実ピクセルを DPR 倍にしないと線がぼやける。
  // サイズ変更すると内容が消えるため、退避 → 復元する。
  resize() {
    const data = this.pad.isEmpty() ? null : this.pad.toData()
    const ratio = Math.max(window.devicePixelRatio || 1, 1)
    const rect = this.canvasTarget.getBoundingClientRect()

    this.canvasTarget.width = rect.width * ratio
    this.canvasTarget.height = rect.height * ratio
    this.canvasTarget.getContext("2d").scale(ratio, ratio)

    this.pad.clear()
    if (data) this.pad.fromData(data)
    this.updateState()
  }

  clear() {
    this.pad.clear()
    this.setStatus("")
    this.updateState()
  }

  updateState() {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = this.pad.isEmpty() || this.submitting
    }
  }

  async submit() {
    if (this.pad.isEmpty() || this.submitting) return
    this.submitting = true
    this.updateState()
    this.setStatus("送信中…")

    const body = new FormData()
    body.append("signature_image", this.pad.toDataURL("image/png"))
    body.append("signature_strokes", JSON.stringify(this.pad.toData()))

    try {
      const res = await fetch(this.submitUrlValue, {
        method: "POST",
        body,
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content,
          "Accept": "application/json"
        }
      })

      if (res.ok) {
        const { redirect_to } = await res.json()
        window.location.href = redirect_to
        return
      }

      const { errors } = await res.json().catch(() => ({ errors: ["送信に失敗しました"] }))
      this.setStatus(errors.join(" / "))
    } catch (_e) {
      // 通信断。署名は消さずに残し、再送できるようにする
      this.setStatus("通信に失敗しました。電波状況を確認して、もう一度お試しください。")
    } finally {
      this.submitting = false
      this.updateState()
    }
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}

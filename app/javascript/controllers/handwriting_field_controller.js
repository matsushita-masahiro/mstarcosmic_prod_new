import { Controller } from "@hotwired/stimulus"
import SignaturePad from "signature_pad"

// 自由記述欄。ペン手書きとキーボード入力を切り替えられる。
export default class extends Controller {
  static targets = ["canvas", "textarea", "penTab", "keyboardTab", "penPane", "keyboardPane"]
  static values = { key: String, mode: { type: String, default: "pen" } }

  connect() {
    this.pad = new SignaturePad(this.canvasTarget, {
      minWidth: 0.6,
      maxWidth: 2.2,
      throttle: 8,
      penColor: "#111827",
      backgroundColor: "rgba(0,0,0,0)"
    })

    this.penSeen = false
    this.pad.addEventListener("endStroke", () => this.notifyChange())

    // パームリジェクション：Pencil を検知したら以降の指入力を無視
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

    // 幅が 0 → 正 に変わった瞬間を捉える。
    // connect 時にレイアウトが確定していない場合と、条件付き表示で
    // 後から現れた場合の両方の保険になる。
    if (typeof ResizeObserver !== "undefined") {
      this.observer = new ResizeObserver(() => this.resize())
      this.observer.observe(this.canvasTarget)
    }

    this.lastWidth = 0
    this.resize()
    this.applyMode()
  }

  disconnect() {
    this.canvasTarget.removeEventListener("pointerdown", this.onPointerDown, true)
    window.removeEventListener("resize", this.onResize)
    window.removeEventListener("orientationchange", this.onResize)
    this.observer?.disconnect()
    this.pad?.off()
  }

  // Retina 対応。canvas の実ピクセルを DPR 倍にしないと線がぼやける。
  // サイズ変更で内容が消えるため退避・復元する。
  resize() {
    const rect = this.canvasTarget.getBoundingClientRect()
    if (rect.width === 0) return                     // 非表示時はスキップ
    if (rect.width === this.lastWidth) return        // 同じ幅なら退避・復元を省く
    this.lastWidth = rect.width

    const data = this.pad.isEmpty() ? null : this.pad.toData()
    const ratio = Math.max(window.devicePixelRatio || 1, 1)

    this.canvasTarget.width = rect.width * ratio
    this.canvasTarget.height = rect.height * ratio
    this.canvasTarget.getContext("2d").scale(ratio, ratio)

    this.pad.clear()
    if (data) this.pad.fromData(data)
  }

  usePen() {
    this.modeValue = "pen"
    this.applyMode()
    // 非表示だった canvas はサイズ 0 なので、表示後に測り直す
    requestAnimationFrame(() => this.resize())
  }

  useKeyboard() {
    this.modeValue = "keyboard"
    this.applyMode()
    this.textareaTarget.focus()
  }

  applyMode() {
    const isPen = this.modeValue === "pen"
    if (this.hasPenPaneTarget) this.penPaneTarget.hidden = !isPen
    if (this.hasKeyboardPaneTarget) this.keyboardPaneTarget.hidden = isPen
    if (this.hasPenTabTarget) this.penTabTarget.classList.toggle("is-active", isPen)
    if (this.hasKeyboardTabTarget) this.keyboardTabTarget.classList.toggle("is-active", !isPen)
  }

  clear() {
    if (this.modeValue === "pen") {
      this.pad.clear()
    } else {
      this.textareaTarget.value = ""
    }
    this.notifyChange()
  }

  notifyChange() {
    this.dispatch("changed", { detail: { key: this.keyValue }, prefix: "handwriting-field" })
  }

  serialize() {
    if (this.modeValue === "keyboard") {
      const text = this.textareaTarget.value
      return text.trim() ? { mode: "keyboard", text } : null
    }
    if (this.pad.isEmpty()) return null

    const rect = this.canvasTarget.getBoundingClientRect()
    return {
      mode: "pen",
      strokes: this.pad.toData(),
      image: this.pad.toDataURL("image/png"),
      width: Math.round(rect.width),
      height: Math.round(rect.height)
    }
  }

  restore(data) {
    if (!data) return
    if (data.mode === "keyboard") {
      this.textareaTarget.value = data.text || ""
      this.modeValue = "keyboard"
    } else if (data.strokes) {
      this.pad.fromData(data.strokes)
      this.modeValue = "pen"
    }
    this.applyMode()
  }
}

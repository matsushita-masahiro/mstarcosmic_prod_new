import { Controller } from "@hotwired/stimulus"
import SignaturePad from "signature_pad"

// 自由記述欄。ペン手書きとキーボード入力を切り替えられる。
//
// <div data-controller="handwriting-field" data-handwriting-field-key-value="q1_purpose">
//   <div data-handwriting-field-target="tabs">…</div>
//   <canvas data-handwriting-field-target="canvas"></canvas>
//   <textarea data-handwriting-field-target="textarea"></textarea>
// </div>
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

    this.resize()
    this.applyMode()
  }

  disconnect() {
    this.canvasTarget.removeEventListener("pointerdown", this.onPointerDown, true)
    window.removeEventListener("resize", this.onResize)
    window.removeEventListener("orientationchange", this.onResize)
    this.pad?.off()
  }

  resize() {
    const data = this.pad.isEmpty() ? null : this.pad.toData()
    const ratio = Math.max(window.devicePixelRatio || 1, 1)
    const rect = this.canvasTarget.getBoundingClientRect()
    if (rect.width === 0) return   // 非表示時はスキップ

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
    // 親（questionnaire コントローラ）に変更を伝え、自動保存をトリガする
    this.dispatch("changed", { detail: { key: this.keyValue }, prefix: "handwriting-field" })
  }

  // 親から呼ばれる。保存用のデータを返す。
  serialize() {
    if (this.modeValue === "keyboard") {
      return { mode: "keyboard", text: this.textareaTarget.value }
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

  // 下書き復元用
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

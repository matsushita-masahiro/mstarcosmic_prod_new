import { Controller } from "@hotwired/stimulus"
import SignaturePad from "signature_pad"

// 署名前に出す案内。updateState が消していいのはこの文言だけ。
const EMPTY_HINT = "ご署名いただくと送信できます。"

// iPad + Apple Pencil / 指での署名入力。
//
// 【前版からの修正】
// connect 時に getBoundingClientRect() が 0 を返す状態で resize() が走ると
// canvas が 0×0 になり、指でなぞっても線が出ない。
// 同意書ページは本文が長く、レイアウト確定やフォント読み込みが
// Stimulus の connect より後になることがあるため実際に踏んだ。
// 画面を回転させたりアドレスバーが伸縮すると resize イベントで測り直され、
// そこで初めて書けるようになるため「スクロールしたら直った」ように見えていた。
//
// 対策は3つ。
//   1. 幅0のときは測り直しをスキップする（0×0 で確定させない）
//   2. ResizeObserver で幅が確定した時点を捉えて測り直す
//   3. フォント読み込み完了後にも一度測り直す
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
    this.lastWidth = 0

    // updateState が出した案内。消していいのはこれと一致するものだけ
    this.shownHint = null

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

    // 幅が 0 → 正 に変わった瞬間を捉える。
    // connect の時点でレイアウトが確定していない場合の保険。
    if (typeof ResizeObserver !== "undefined") {
      this.observer = new ResizeObserver(() => this.resize())
      this.observer.observe(this.canvasTarget)
    }

    // Web フォントの読み込みで行の高さが変わり、署名欄の位置がずれることがある
    document.fonts?.ready?.then(() => this.resize())

    this.resize()
    this.updateState()
  }

  disconnect() {
    this.canvasTarget.removeEventListener("pointerdown", this.onPointerDown, true)
    window.removeEventListener("resize", this.onResize)
    window.removeEventListener("orientationchange", this.onResize)
    this.observer?.disconnect()
    this.pad?.off()
  }

  // Retina 対応。canvas の実ピクセルを DPR 倍にしないと線がぼやける。
  // サイズ変更すると内容が消えるため、退避 → 復元する。
  resize() {
    const rect = this.canvasTarget.getBoundingClientRect()

    // 幅が取れないうちに測ると 0×0 で固まる。ResizeObserver が後で拾う。
    if (rect.width === 0) return
    // 同じ幅で測り直すとストロークの退避・復元が無駄に走る
    if (rect.width === this.lastWidth) return
    this.lastWidth = rect.width

    const data = this.pad.isEmpty() ? null : this.pad.toData()
    const ratio = Math.max(window.devicePixelRatio || 1, 1)

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

  // 送信ボタンの状態と、押せない理由の表示。
  // disabled なボタンは押しても無反応で理由が分からないため、
  // 何をすれば送れるのかを文言で出す。
  //
  // 消していいのは自分が出した案内だけ。無条件に空文字で上書きすると、
  // 送信失敗のエラーを直後の updateState（submit の finally）で消してしまう。
  updateState() {
    if (!this.hasSubmitTarget) return

    const hint = this.blockedHint()
    this.submitTarget.disabled = hint !== null || this.submitting

    if (this.submitting) return

    if (hint !== null) {
      this.shownHint = hint
      this.setStatus(hint)
    } else if (this.currentStatus() === this.shownHint) {
      this.shownHint = null
      this.setStatus("")
    }
  }

  // 送信できない理由。送れる状態なら null。
  //
  // 署名だけでなく、署名と一緒に送る入力欄（問診票の署名者名など）も見る。
  // 同意書には data-signature-pad-required を持つ要素が無いので、
  // 従来どおり「署名が空かどうか」だけで決まる。
  blockedHint() {
    if (this.pad.isEmpty()) return EMPTY_HINT

    const missing = Array.from(this.element.querySelectorAll("[data-signature-pad-required]"))
                         .find((el) => el.value.trim() === "")

    // 属性の値が、空のときに出す案内文になる
    return missing ? missing.dataset.signaturePadRequired : null
  }

  // 署名と一緒に送る値。
  // data-signature-pad-field="signer_name" を付けた入力を、その名前で載せる。
  // ラジオ・チェックボックスは選ばれているものだけを見る。
  extraFields() {
    const fields = {}
    this.element.querySelectorAll("[data-signature-pad-field]").forEach((el) => {
      if ((el.type === "radio" || el.type === "checkbox") && !el.checked) return
      fields[el.dataset.signaturePadField] = el.value
    })
    return fields
  }

  currentStatus() {
    return this.hasStatusTarget ? this.statusTarget.textContent : ""
  }

  async submit() {
    if (this.blockedHint() !== null || this.submitting) return
    this.submitting = true
    this.submitTarget.disabled = true
    this.setStatus("送信中…")

    const body = new FormData()
    body.append("signature_image", this.pad.toDataURL("image/png"))
    // toData() をそのまま送る。座標だけに間引かないこと。
    // 各点の time から筆速・筆順が復元でき、模倣筆跡の検出はここに依存している。
    body.append("signature_strokes", JSON.stringify(this.pad.toData()))

    Object.entries(this.extraFields()).forEach(([name, value]) => body.append(name, value))

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

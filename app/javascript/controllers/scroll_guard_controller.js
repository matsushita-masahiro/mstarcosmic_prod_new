import { Controller } from "@hotwired/stimulus"

// 同意書を最後までスクロールしたことを検知して枠線の警告色を外す。
// 「読んだことにする」ための UI であり、法的な既読証明ではない点に注意。
export default class extends Controller {
  static targets = ["doc", "hint"]

  connect() {
    this.check()
  }

  check() {
    const el = this.docTarget
    const reachedBottom = el.scrollTop + el.clientHeight >= el.scrollHeight - 8
    if (reachedBottom || el.scrollHeight <= el.clientHeight) {
      el.classList.remove("is-unread")
      if (this.hasHintTarget) this.hintTarget.textContent = ""
    }
  }
}

import { Controller } from "@hotwired/stimulus"

// 条件付き表示。
// data-depends-on / data-depends-value を持つ要素を、
// 親の設問の回答に応じて出し分ける。
//
// 例: 【8】喫煙で「吸う」を選んだときだけ本数のプルダウンを出す
//
// 【前版からの修正】
// 隠れている canvas は getBoundingClientRect().width が 0 になるため、
// handwriting_field_controller の resize() は早期 return する。
// つまり条件付きで後から現れた手書き欄は canvas が 0×0 のままになり、
// ペンで書いても何も出ない。【17】のサブ項目は全て手書きなので影響が大きい。
// 非表示→表示に変わった瞬間に、内側の handwriting-field を測り直させる。
export default class extends Controller {
  connect() {
    this.fields = Array.from(this.element.querySelectorAll('[data-conditional="true"]'))
    this.onChange = () => this.apply()
    this.element.addEventListener("change", this.onChange)
    this.apply()
  }

  disconnect() {
    this.element.removeEventListener("change", this.onChange)
  }

  apply() {
    this.fields.forEach((field) => {
      const key = field.dataset.dependsOn
      const expected = field.dataset.dependsValue.split(",")
      const checked = this.element.querySelector(`[name="answers[${key}]"]:checked`)
      const shouldShow = !!(checked && expected.includes(checked.value))
      const wasHidden = field.hidden

      field.hidden = !shouldShow

      // 非表示にした項目の値はクリアする。
      // 「吸う→本数入力→吸わないに変更」で本数が残るのを防ぐ。
      if (!shouldShow) {
        this.clearInputs(field)
        return
      }

      // 表示に変わったフレームで canvas を測り直す。
      // hidden を外した直後はまだレイアウトが確定していないため rAF で待つ。
      if (wasHidden) {
        requestAnimationFrame(() => this.resizeCanvases(field))
      }
    })
  }

  clearInputs(container) {
    container.querySelectorAll("input, select, textarea").forEach((el) => {
      if (el.type === "radio" || el.type === "checkbox") {
        el.checked = false
      } else {
        el.value = ""
      }
    })
  }

  resizeCanvases(container) {
    container.querySelectorAll('[data-controller~="handwriting-field"]').forEach((el) => {
      const ctrl = this.application.getControllerForElementAndIdentifier(el, "handwriting-field")
      ctrl?.resize()
    })
  }
}

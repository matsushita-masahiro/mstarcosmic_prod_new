import { Controller } from "@hotwired/stimulus"

// 人体図（表・裏）へのマーキング。
// 座標は 0.0〜1.0 の相対値で保持し、解像度に依存させない。
// これにより「前回と比べて痛みの位置が変わったか」を機械的に比較できる。
export default class extends Controller {
  static targets = ["front", "back", "list", "typeSelect"]

  connect() {
    this.marks = []
    this.frontTarget.addEventListener("click", (e) => this.addMark(e, "front"))
    this.backTarget.addEventListener("click", (e) => this.addMark(e, "back"))
    this.render()
  }

  addMark(event, side) {
    const svg = event.currentTarget
    const rect = svg.getBoundingClientRect()
    const x = (event.clientX - rect.left) / rect.width
    const y = (event.clientY - rect.top) / rect.height
    if (x < 0 || x > 1 || y < 0 || y > 1) return

    const markType = this.hasTypeSelectTarget ? this.typeSelectTarget.value : "pain"
    this.marks.push({ side, x, y, mark_type: markType })
    this.render()
    this.dispatch("changed", { prefix: "body-map" })
  }

  removeMark(event) {
    const index = Number(event.currentTarget.dataset.index)
    this.marks.splice(index, 1)
    this.render()
    this.dispatch("changed", { prefix: "body-map" })
  }

  clear() {
    this.marks = []
    this.render()
    this.dispatch("changed", { prefix: "body-map" })
  }

  render() {
    // 既存のマークを消して描き直す
    this.element.querySelectorAll(".body-mark").forEach((el) => el.remove())

    this.marks.forEach((mark, index) => {
      const svg = mark.side === "front" ? this.frontTarget : this.backTarget
      const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle")
      circle.setAttribute("cx", mark.x * 100)
      circle.setAttribute("cy", mark.y * 100)
      circle.setAttribute("r", 2.2)
      circle.setAttribute("fill", this.colorFor(mark.mark_type))
      circle.setAttribute("fill-opacity", "0.65")
      circle.setAttribute("stroke", this.colorFor(mark.mark_type))
      circle.setAttribute("stroke-width", "0.5")
      circle.setAttribute("class", "body-mark")
      circle.dataset.index = index
      circle.style.cursor = "pointer"
      circle.addEventListener("click", (e) => {
        e.stopPropagation()
        this.marks.splice(index, 1)
        this.render()
        this.dispatch("changed", { prefix: "body-map" })
      })
      svg.appendChild(circle)
    })

    if (this.hasListTarget) {
      this.listTarget.textContent = this.marks.length
        ? `${this.marks.length} か所（マークをタップすると削除できます）`
        : "図の気になる場所をタップしてください"
    }
  }

  colorFor(type) {
    return { pain: "#dc2626", numbness: "#2563eb", stiffness: "#d97706", other: "#6b7280" }[type] || "#dc2626"
  }

  serialize() {
    return this.marks
  }

  restore(marks) {
    this.marks = Array.isArray(marks) ? marks : []
    this.render()
  }
}

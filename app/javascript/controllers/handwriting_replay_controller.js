import { Controller } from "@hotwired/stimulus"

// 手書き回答を strokes から canvas に描き直す。
//
// PNG をそのまま出すのをやめた理由は2つある。
//   1. 記入時より canvas が狭いと PNG が保存されない（切れた画像を残さないため）。
//      その欄はこれまで「（手書きあり・画像なし）」としか出せず、患者は
//      自分が書いたものを確認できないまま署名していた。strokes は全点が
//      残っているので、そこから描けば読める。
//   2. 版をまたいだときに、前の版から引き継いだ線と今回書き足した線を
//      色で分けられる。
//
// signature_pad は使わない。ここでやるのは読み取って線を引くことだけで、
// 筆圧の可変幅やベジエ補間は要らない。記入側
// （handwriting_field_controller）ともコードを共有しない。描く目的が違う。
//
// ── 色分けの出し分け ────────────────────────────
//
// boundary（境界インデックス）を渡されたときだけ色が分かれる。
// 渡されなければ全部を同じ色で描く。真偽のフラグにしていないのは、
// 1箇所間違えると患者の画面に色が出るため。境界が無ければ色分けの
// しようがない、という形にしてある。渡し忘れれば単色に倒れる。
export default class extends Controller {
  static targets = ["canvas", "legend"]
  static values = {
    strokes: { type: Array, default: [] },
    width: { type: Number, default: 0 },
    height: { type: Number, default: 0 },
    // 境界。この位置以降のストロークが「今回書き足したぶん」。
    // 属性が無ければ hasBoundaryValue が false になり、単色で描く。
    boundary: Number
  }

  // 元からあった線。本文と同じ濃さの黒。
  static INHERITED_COLOR = "#111827"
  // 今回書き足した線。赤は禁忌、黄は要確認に割り当て済みなので青にする。
  static ADDED_COLOR = "#1d4ed8"

  connect() {
    this.draw()
    // 折りたたみの中や幅可変の欄に置かれるため、幅が変わったら描き直す。
    this.observer = new ResizeObserver(() => this.draw())
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  draw() {
    const canvas = this.canvasTarget
    const sourceWidth = this.widthValue
    const sourceHeight = this.heightValue
    if (!sourceWidth || !sourceHeight) return

    const displayWidth = this.element.clientWidth
    if (!displayWidth) return

    // 記入時の canvas 幅に対する倍率。canvas_width は端末で変わるので
    // 固定値を前提にしない（実データで 334 と 353 の2種類が出ている）。
    const scale = displayWidth / sourceWidth
    const displayHeight = sourceHeight * scale

    // Retina 対応。実ピクセルを DPR 倍にしないと線がぼやける。
    const ratio = Math.max(window.devicePixelRatio || 1, 1)
    canvas.width = displayWidth * ratio
    canvas.height = displayHeight * ratio
    canvas.style.width = `${displayWidth}px`
    canvas.style.height = `${displayHeight}px`

    const ctx = canvas.getContext("2d")
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0)
    ctx.clearRect(0, 0, displayWidth, displayHeight)
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    ctx.lineWidth = 1.6

    const split = this.hasBoundaryValue ? this.boundaryValue : null

    this.strokesValue.forEach((group, index) => {
      const points = this.pointsOf(group)
      if (points.length === 0) return

      const added = split !== null && index >= split
      ctx.strokeStyle = added
        ? this.constructor.ADDED_COLOR
        : this.constructor.INHERITED_COLOR

      ctx.beginPath()
      points.forEach((point, i) => {
        const x = point.x * scale
        const y = point.y * scale
        if (i === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      })

      // 点1つだけのストローク（タップ）は線にならないので丸を打つ。
      if (points.length === 1) {
        ctx.fillStyle = ctx.strokeStyle
        ctx.beginPath()
        ctx.arc(points[0].x * scale, points[0].y * scale, ctx.lineWidth / 2, 0, Math.PI * 2)
        ctx.fill()
        return
      }

      ctx.stroke()
    })
  }

  // signature_pad の toData() は { points: [...] } の配列を返す。
  // 形が違うものが来ても落とさず、描けないものは黙って飛ばす。
  pointsOf(group) {
    const points = Array.isArray(group) ? group : group?.points
    if (!Array.isArray(points)) return []

    return points.filter((p) => Number.isFinite(p?.x) && Number.isFinite(p?.y))
  }
}

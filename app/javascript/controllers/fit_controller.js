import { Controller } from "@hotwired/stimulus"

// Scales the target text up until it fills the container without overflowing. Re-fits on resize
// and whenever the content changes (the operator advances a section).
export default class extends Controller {
  static targets = ["content"]
  static values = { min: { type: Number, default: 12 }, max: { type: Number, default: 240 } }

  connect() {
    this.fit()
    this.resizeObserver = new ResizeObserver(() => this.fit())
    // Observe the bounded stage (the viewport-sized frame) so a window/preview resize refits.
    this.resizeObserver.observe(this.element.closest("#live-frame") || this.element)
  }

  disconnect() {
    this.resizeObserver?.disconnect()
  }

  contentTargetConnected() {
    this.fit()
  }

  fit() {
    // Measure against the BOUNDED stage, not this element. The fit controller sits on
    // .projector-section, which is a flex child that grows to its own content height — so
    // measuring `this.element` makes scrollHeight == clientHeight and the text never shrinks
    // (it overflows the real projector). #live-frame is bounded by the viewport, so use it as
    // the box; fall back to this.element when there is no stage ancestor.
    const stage = this.element.closest("#live-frame") || this.element
    const box = stage
    const content = this.hasContentTarget ? this.contentTarget : this.element
    // Measure the WHOLE section (this.element) against the stage — not just the content target —
    // so a copyright line or title credits sitting beside the content are counted and cannot be
    // pushed off-screen. Font-size is still applied to the content (the lyrics/title block).
    const measured = this.element
    const cs = getComputedStyle(stage)
    const padY = parseFloat(cs.paddingTop) + parseFloat(cs.paddingBottom)
    const padX = parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight)
    const availH = box.clientHeight - padY
    const availW = box.clientWidth - padX
    let lo = this.minValue
    let hi = this.maxValue

    // Binary search the largest font size that does not overflow the stage.
    while (hi - lo > 1) {
      const mid = Math.floor((lo + hi) / 2)
      content.style.fontSize = `${mid}px`
      const fits = measured.scrollHeight <= availH && measured.scrollWidth <= availW
      if (fits) lo = mid; else hi = mid
    }
    content.style.fontSize = `${lo}px`

    // Apply the operator's font-scale override (percent) from the frame, if present.
    const scaleEl = this.element.closest("[data-font-scale]") || this.element.querySelector("[data-font-scale]")
    const scale = scaleEl ? Number(scaleEl.dataset.fontScale) : 100
    if (scale && scale !== 100) {
      content.style.fontSize = `${Math.round(lo * scale / 100)}px`
    }
  }
}

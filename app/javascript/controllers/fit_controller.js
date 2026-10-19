import { Controller } from "@hotwired/stimulus"

// Scales the target text up until it fills the container without overflowing. Re-fits on resize
// and whenever the content changes (the operator advances a section).
export default class extends Controller {
  static targets = ["content"]
  static values = { min: { type: Number, default: 12 }, max: { type: Number, default: 240 } }

  connect() {
    this.fit()
    this.resizeObserver = new ResizeObserver(() => this.fit())
    this.resizeObserver.observe(this.element)
  }

  disconnect() {
    this.resizeObserver?.disconnect()
  }

  contentTargetConnected() {
    this.fit()
  }

  fit() {
    const box = this.element
    const content = this.hasContentTarget ? this.contentTarget : this.element
    let lo = this.minValue
    let hi = this.maxValue

    // Binary search the largest font size that does not overflow.
    while (hi - lo > 1) {
      const mid = Math.floor((lo + hi) / 2)
      content.style.fontSize = `${mid}px`
      const fits = content.scrollHeight <= box.clientHeight && content.scrollWidth <= box.clientWidth
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

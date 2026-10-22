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
    // The real projector stage (#live-frame) is viewport-bounded and has padding; its inner
    // content box is what the lyrics may fill. .projector-section is width:100% of that box, so
    // width is not the constraint — HEIGHT is. We binary-search the largest font size whose
    // rendered section height fits the stage's inner height.
    const stage = this.element.closest("#live-frame") || this.element.parentElement || this.element
    const content = this.hasContentTarget ? this.contentTarget : this.element
    const measured = this.element // the whole section (lyrics + any copyright/credits)

    // Inner (content-box) size of the stage: clientHeight/Width already exclude border and the
    // scrollbar, so subtract only the padding to get the space children actually get.
    const cs = getComputedStyle(stage)
    const padY = parseFloat(cs.paddingTop) + parseFloat(cs.paddingBottom)
    const padX = parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight)
    const availH = stage.clientHeight - padY
    const availW = stage.clientWidth - padX
    if (availH <= 0 || availW <= 0) return // not laid out yet

    let lo = this.minValue
    let hi = this.maxValue

    while (hi - lo > 1) {
      const mid = Math.floor((lo + hi) / 2)
      content.style.fontSize = `${mid}px`
      // HEIGHT is the fill driver. The section is width:100%, so its scrollWidth always equals
      // availW within sub-pixel rounding — only a genuinely unbreakable line (several px past the
      // edge) counts as a width overflow, otherwise width would falsely clamp the font to nothing.
      const heightFits = measured.scrollHeight <= availH
      const widthFits = measured.scrollWidth <= availW + 4
      if (heightFits && widthFits) lo = mid; else hi = mid
    }
    content.style.fontSize = `${lo}px`

    // Apply the operator's font-scale override (percent) from the frame, if present.
    const scaleEl = this.element.closest("[data-font-scale]") || this.element.querySelector("[data-font-scale]")
    const scale = scaleEl ? Number(scaleEl.dataset.fontScale) : 100
    if (scale && scale !== 100) {
      content.style.fontSize = `${Math.round(lo * scale / 100)}px`
    }
  }

    // Apply the operator's font-scale override (percent) from the frame, if present.
    const scaleEl = this.element.closest("[data-font-scale]") || this.element.querySelector("[data-font-scale]")
    const scale = scaleEl ? Number(scaleEl.dataset.fontScale) : 100
    if (scale && scale !== 100) {
      content.style.fontSize = `${Math.round(lo * scale / 100)}px`
    }
  }
}

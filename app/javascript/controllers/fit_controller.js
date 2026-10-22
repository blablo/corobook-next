import { Controller } from "@hotwired/stimulus"

// Scales the target text up until it fills the stage without overflowing. Re-fits on resize and
// whenever the content changes (the operator advances a section). Height is the fill driver: the
// lyric block is width:100% of the stage, so only its height can grow it to fill the screen.
export default class extends Controller {
  static targets = ["content"]
  static values = { min: { type: Number, default: 12 }, max: { type: Number, default: 400 } }

  connect() {
    this.schedule()
    this.resizeObserver = new ResizeObserver(() => this.schedule())
    // Observe the bounded stage (the viewport-sized frame) so a window/preview resize refits.
    this.resizeObserver.observe(this.element.closest("#live-frame") || this.element.closest(".projector-preview") || this.element)
    // Allow another controller (e.g. the slide editor's live preview) to request a refit after
    // it swaps the content HTML, which the ResizeObserver does not see.
    this.refitHandler = () => this.schedule()
    this.element.addEventListener("fit:refit", this.refitHandler)
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.element.removeEventListener("fit:refit", this.refitHandler)
  }

  contentTargetConnected() {
    // Hide the freshly-rendered content until the first fit sizes it, so a slide change never
    // flashes the small default size before the resize lands.
    this.contentTarget.style.visibility = "hidden"
    this.schedule()
  }

  // Defer to after layout: the flex stage (#live-frame) may not have its final height on connect.
  schedule() {
    requestAnimationFrame(() => requestAnimationFrame(() => this.fit()))
  }

  fit() {
    const stage = this.element.closest("#live-frame") || this.element.closest(".projector-preview") || this.element.parentElement || this.element
    const content = this.hasContentTarget ? this.contentTarget : this.element
    const measured = this.element // the whole section (lyrics + any copyright/credits)

    // Inner (content-box) size of the stage. clientHeight/Width exclude border and scrollbar, so
    // subtract the padding to get the space children actually get.
    const cs = getComputedStyle(stage)
    const padY = parseFloat(cs.paddingTop) + parseFloat(cs.paddingBottom)
    const padX = parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight)
    const availH = stage.clientHeight - padY
    const availW = stage.clientWidth - padX
    if (availH <= 1 || availW <= 1) {
      // Not laid out yet — do not leave the content hidden; reveal and try again next frame.
      content.style.visibility = "visible"
      this.schedule()
      return
    }

    let lo = this.minValue
    let hi = this.maxValue

    while (hi - lo > 1) {
      const mid = Math.floor((lo + hi) / 2)
      content.style.fontSize = `${mid}px`
      // Height drives the fill. Width only guards a genuinely unbreakable line (the width:100%
      // section always equals availW within rounding, so use a small tolerance).
      const heightFits = measured.scrollHeight <= availH
      const widthFits = measured.scrollWidth <= availW + 4
      if (heightFits && widthFits) lo = mid
      else hi = mid
    }
    content.style.fontSize = `${lo}px`

    // Apply the operator's font-scale override (percent) from the frame, if present.
    const scaleEl = this.element.closest("[data-font-scale]") || this.element.querySelector("[data-font-scale]")
    const scale = scaleEl ? Number(scaleEl.dataset.fontScale) : 100
    if (scale && scale !== 100) {
      content.style.fontSize = `${Math.round(lo * scale / 100)}px`
    }

    // Now that it is correctly sized, reveal it (no small→big flash on slide change).
    content.style.visibility = "visible"
  }
}

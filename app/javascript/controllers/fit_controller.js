import { Controller } from "@hotwired/stimulus"

// Song sizes already worked out, keyed by song + stage size + settings. The projector frame is
// re-rendered on every slide change, so the cache lives outside the controller instance.
const songSizes = new Map()

// Sizes projector text. Re-fits on resize and whenever the content changes (the operator
// advances a slide).
//
// * Song lyric slides (songKey set): ONE size for every slide of the song. All of the song's
//   slides are measured once (from the invisible .projector-measure copy in the frame) and the
//   largest size that fits all of them is used, capped at the church's preferred size and never
//   below its minimum. Sections too long for the minimum were already split onto more slides
//   by the server.
// * Anything else (text slides, previews): a fixed size, or as large as this slide allows.
export default class extends Controller {
  static targets = ["content"]
  // fixed: preferred/fixed size as % of the stage height; 0 = as large as fits.
  // minPct: smallest song size as % of the stage height. songKey: identifies the song.
  static values = {
    min: { type: Number, default: 12 },
    max: { type: Number, default: 400 },
    fixed: { type: Number, default: 0 },
    minPct: { type: Number, default: 0 },
    songKey: { type: String, default: "" }
  }

  // The slide editor changes data-fit-fixed-value as the size select changes; refit live.
  fixedValueChanged() {
    if (this.resizeObserver) this.schedule()
  }

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
    const content = this.hasContentTarget ? this.contentTarget : this.element
    const stage = this.element.closest("#live-frame") || this.element.closest(".projector-preview") || this.element.parentElement || this.element

    // Fixed size outside a song: a percentage of the stage height via container-query units,
    // so it is the same proportion of the screen on the projector and every preview.
    if (this.fixedValue > 0 && !this.songKeyValue) {
      content.style.fontSize = `${this.fixedValue}cqh`
      content.style.visibility = "visible"
      return
    }

    // Inner (content-box) size of the stage: the space the text actually gets.
    const cs = getComputedStyle(stage)
    const availH = stage.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom)
    const availW = stage.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight)
    if (availH <= 1 || availW <= 1) {
      // Not laid out yet — do not leave the content hidden; reveal and try again next frame.
      content.style.visibility = "visible"
      this.schedule()
      return
    }

    const fits = (el) => el.scrollHeight <= availH && el.scrollWidth <= availW + 4
    let size = this.songKeyValue
      ? this.songSize(stage, content, availW, availH)
      : this.largestFitting(content, this.element, fits, this.maxValue)

    // Safety net: if this slide still overflows at the song size (the credits line on the last
    // slide, or an unusually wide word), shrink this one slide just enough.
    content.style.fontSize = `${size}px`
    if (!fits(this.element)) size = this.largestFitting(content, this.element, fits, size)

    // Apply the operator's font-scale override (percent) from the frame, if present.
    const scaleEl = this.element.closest("[data-font-scale]") || this.element.querySelector("[data-font-scale]")
    const scale = scaleEl ? Number(scaleEl.dataset.fontScale) : 100
    content.style.fontSize = `${scale && scale !== 100 ? Math.round(size * scale / 100) : size}px`

    // Now that it is correctly sized, reveal it (no small→big flash on slide change).
    content.style.visibility = "visible"
  }

  // The one size for every slide of this song, in px.
  songSize(stage, content, availW, availH) {
    const cap = this.fixedValue > 0 ? this.pctToPx(content, this.fixedValue) : this.maxValue
    const floor = this.minPctValue > 0 ? this.pctToPx(content, this.minPctValue) : this.minValue
    const key = `${this.songKeyValue}|${Math.round(availW)}x${Math.round(availH)}|${cap}|${floor}`
    if (songSizes.has(key)) return songSizes.get(key)

    let size = cap
    const measure = stage.querySelector('[data-role="fit-measure"]')
    if (measure) {
      measure.style.width = `${availW}px`
      const fits = (el) => el.scrollHeight <= availH && el.scrollWidth <= availW + 4
      measure.querySelectorAll('[data-role="fit-measure-slide"]').forEach((slide) => {
        size = Math.min(size, this.largestFitting(slide, slide, fits, size))
      })
    }
    size = Math.max(size, floor)
    songSizes.set(key, size)
    return size
  }

  // Largest whole-px font size (up to `cap`) at which `measured` fits, sizing `target`.
  largestFitting(target, measured, fits, cap) {
    let lo = this.minValue
    let hi = cap + 1
    while (hi - lo > 1) {
      const mid = Math.floor((lo + hi) / 2)
      target.style.fontSize = `${mid}px`
      if (fits(measured)) lo = mid
      else hi = mid
    }
    target.style.fontSize = `${lo}px`
    return lo
  }

  // A % of the stage height (cqh, as stored in the settings) in px, read from the browser so it
  // matches what the fixed-size path renders.
  pctToPx(el, pct) {
    const previous = el.style.fontSize
    el.style.fontSize = `${pct}cqh`
    const px = parseFloat(getComputedStyle(el).fontSize)
    el.style.fontSize = previous
    return Math.round(px)
  }
}

import { Controller } from "@hotwired/stimulus"

// Hides the musician page's sticky header (the top bar and the Now/Next band) while reading down
// the chart and brings it back on any scroll up, like a phone browser's address bar. The red
// edge on the live row still shows where the service is. Near the top of the page the header
// always shows.
const MIN_DELTA = 6 // px of scroll before reacting, so a shaky thumb does not flicker the header
const ALWAYS_SHOWN_ABOVE = 48 // px from the top

export default class extends Controller {
  connect() {
    this.lastY = window.scrollY
    this.onScroll = () => {
      if (this.ticking) return
      this.ticking = true
      requestAnimationFrame(() => this.update())
    }
    window.addEventListener("scroll", this.onScroll, { passive: true })
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
  }

  update() {
    this.ticking = false
    const y = window.scrollY
    const delta = y - this.lastY
    if (Math.abs(delta) < MIN_DELTA) return

    this.element.classList.toggle("header-hidden", delta > 0 && y > ALWAYS_SHOWN_ABOVE)
    this.lastY = y
  }
}

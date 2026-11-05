import { Controller } from "@hotwired/stimulus"

// Auto-advancing text slide: shows page floor((now - since) / seconds), wrapping when it loops or
// holding the last page when it does not. Every screen computes the page from the same server
// timestamp, so the projector, the operator preview and a reloaded screen all agree, and the
// server sends nothing while the pages turn. serverNow corrects for this browser's clock drift.
// Dispatches auto-pages:change { page, count } so the operator's label can follow along.
export default class extends Controller {
  static targets = ["page"]
  static values = { seconds: Number, loop: Boolean, since: Number, serverNow: Number }

  connect() {
    this.offset = this.serverNowValue ? this.serverNowValue - Date.now() : 0
    this.start = this.sinceValue || this.now()
    this.current = -1
    this.tick()
    this.timer = setInterval(() => this.tick(), 250)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  now() { return Date.now() + this.offset }

  tick() {
    const count = this.pageTargets.length
    if (count < 2 || !this.secondsValue) return

    const step = Math.floor(Math.max(0, this.now() - this.start) / (this.secondsValue * 1000))
    const page = this.loopValue ? step % count : Math.min(step, count - 1)
    if (page === this.current) return

    this.current = page
    this.pageTargets.forEach((el, i) => {
      el.classList.toggle("is-on", i === page)
      el.setAttribute("aria-hidden", i === page ? "false" : "true")
    })
    this.dispatch("change", { detail: { page, count } })
  }
}

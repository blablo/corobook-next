import { Controller } from "@hotwired/stimulus"

// A countdown field inside a text slide (see Corobook::SlideCountdown).
//  - to "10:30": counts down to that time of day on THIS computer's own clock, so the screens in
//    the room (all set to local time) show the same thing without a time zone setting. If 10:30
//    has already passed today it shows the end text; more than 12 hours past means tomorrow.
//  - minutes 5: counts down from when the slide went live (the frame's data-live-since, corrected
//    by data-server-now), so every screen agrees; in an editor preview it starts on load.
// At zero it shows the end text (or holds 00:00) and never moves the service on by itself.
// Dispatches countdown:tick { text, done } so the operator badge can follow along.
export default class extends Controller {
  static values = { to: String, minutes: Number, end: String }

  connect() {
    this.target = this.computeTarget()
    this.last = null
    this.tick()
    this.timer = setInterval(() => this.tick(), 250)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  computeTarget() {
    if (this.toValue) {
      const [h, m] = this.toValue.split(":").map(Number)
      const t = new Date()
      t.setHours(h, m, 0, 0)
      if (Date.now() - t.getTime() > 12 * 3600 * 1000) t.setDate(t.getDate() + 1)
      this.offset = 0
      return t.getTime()
    }
    const host = this.element.closest("[data-live-since]")
    const since = Number(host?.dataset.liveSince) || 0
    const serverNow = Number(host?.dataset.serverNow) || 0
    this.offset = serverNow ? serverNow - Date.now() : 0
    const start = since || this.now()
    return start + (this.minutesValue || 0) * 60 * 1000
  }

  now() { return Date.now() + (this.offset || 0) }

  tick() {
    const left = this.target - this.now()
    const done = left <= 0
    const text = done ? (this.endValue || "00:00") : this.format(left)
    if (text === this.last) return

    const wasDone = this.last !== null && this.element.dataset.done === "true"
    this.last = text
    this.element.textContent = text
    this.element.dataset.done = String(done)
    // The end text can be wider than the digits: let the slide's fit controller resize once.
    if (done && !wasDone) this.element.dispatchEvent(new CustomEvent("fit:refit", { bubbles: true }))
    this.dispatch("tick", { detail: { text: done ? null : text, done } })
  }

  format(ms) {
    const s = Math.ceil(ms / 1000)
    const h = Math.floor(s / 3600)
    const m = Math.floor((s % 3600) / 60)
    const r = s % 60
    const pad = (n) => String(n).padStart(2, "0")
    return h ? `${h}:${pad(m)}:${pad(r)}` : `${pad(m)}:${pad(r)}`
  }
}

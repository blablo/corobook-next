import { Controller } from "@hotwired/stimulus"

// Wall clock for the operator's presenter view (Keynote-style), so whoever runs the service
// can keep time. Uses the browser's local time and the page language for the format.
export default class extends Controller {
  connect() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    const lang = document.documentElement.lang || undefined
    this.element.textContent = new Date().toLocaleTimeString(lang, { hour: "2-digit", minute: "2-digit" })
  }
}

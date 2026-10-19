import { Controller } from "@hotwired/stimulus"

// Auto-dismisses a flash message after a delay, with a fade-out.
// Usage: <div data-controller="flash" data-flash-delay-value="4000"> ... </div>
export default class extends Controller {
  static values = { delay: { type: Number, default: 4000 } }

  connect() {
    this.timeout = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
  }

  dismiss() {
    this.element.classList.add("transition-opacity", "duration-500", "opacity-0")
    this.element.addEventListener("transitionend", () => this.element.remove(), { once: true })
    // Fallback in case transitionend doesn't fire.
    setTimeout(() => this.element.remove(), 600)
  }
}

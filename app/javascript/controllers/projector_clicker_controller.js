import { Controller } from "@hotwired/stimulus"

// Drives the live service from a token-gated screen: the PROJECTOR page, for the common setup
// where the presentation clicker is plugged into the projection machine, and the speaker view's
// Next/Back buttons. Clickers emit key events; we PATCH them to the token-gated advance/back
// endpoints (possession of the token is the capability to drive). The follower stream then
// updates this page and every other follower.
//
// keys: false turns the keyboard off (the speaker view, where Space on a focused button would
// otherwise move twice).
export default class extends Controller {
  static values = { advanceUrl: String, backUrl: String, keys: { type: Boolean, default: true } }

  connect() {
    if (!this.keysValue) return
    this.onKey = this.handleKey.bind(this)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    if (this.onKey) document.removeEventListener("keydown", this.onKey)
  }

  handleKey(e) {
    if (e.metaKey || e.ctrlKey || e.altKey) return
    const key = e.key
    if (key === "PageDown" || key === "ArrowRight" || key === "ArrowDown" || key === " " || key === "Spacebar") {
      this.post(this.advanceUrlValue, e)
    } else if (key === "PageUp" || key === "ArrowLeft" || key === "ArrowUp" || key === "Backspace") {
      this.post(this.backUrlValue, e)
    }
  }

  // Buttons: data-action="projector-clicker#next" / "projector-clicker#back".
  next(e) { this.post(this.advanceUrlValue, e) }
  back(e) { this.post(this.backUrlValue, e) }

  post(url, e) {
    if (!url) return
    e.preventDefault()
    fetch(url, { method: "PATCH", headers: { Accept: "text/vnd.turbo-stream.html" } })
  }
}

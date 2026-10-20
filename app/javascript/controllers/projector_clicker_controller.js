import { Controller } from "@hotwired/stimulus"

// Drives the live service from the PROJECTOR page itself, for the common setup where the
// presentation clicker is plugged into the projection machine. Clickers emit key events; we
// POST them to the token-gated advance/back endpoints (possession of the projector token is the
// capability to drive). The follower stream then updates this page and every other follower.
export default class extends Controller {
  static values = { advanceUrl: String, backUrl: String }

  connect() {
    this.onKey = this.handleKey.bind(this)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
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

  post(url, e) {
    if (!url) return
    e.preventDefault()
    fetch(url, { method: "PATCH", headers: { Accept: "text/vnd.turbo-stream.html" } })
  }
}
